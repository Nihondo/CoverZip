//
//  ThumbnailStripView.swift
//  coverZipViewer
//

import Cocoa

/// サムネイルストリップ上端のドラッグリサイズハンドル
private final class ThumbnailResizeHandle: NSView {

    var onResizeDragged: ((CGFloat) -> Void)?
    var onResizeDragEnded: (() -> Void)?

    private var dragStartY: CGFloat = 0
    private var isDragging = false
    private var isHoverCursorPushed = false
    private var isDragCursorPushed = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 上端（imageViewとの境界）に 1pt のセパレータを描画
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isDragging, !isHoverCursorPushed else { return }
        NSCursor.resizeUpDown.push()
        isHoverCursorPushed = true
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        if isHoverCursorPushed {
            NSCursor.pop()
            isHoverCursorPushed = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStartY = event.locationInWindow.y
        NSCursor.resizeUpDown.push()
        isDragCursorPushed = true
    }

    override func mouseDragged(with event: NSEvent) {
        let currentY = event.locationInWindow.y
        let delta = currentY - dragStartY
        dragStartY = currentY
        onResizeDragged?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        // ドラッグ開始時の push を解除
        if isDragCursorPushed {
            NSCursor.pop()
            isDragCursorPushed = false
        }
        // ドラッグ中に mouseExited が抑制されていた場合、ハンドル外でリリースされたら hover push も解除
        let locationInSelf = convert(event.locationInWindow, from: nil)
        if !bounds.contains(locationInSelf), isHoverCursorPushed {
            NSCursor.pop()
            isHoverCursorPushed = false
        }
        onResizeDragEnded?()
    }
}

/// サムネイルストリップ内で左右カーソルキーを確実に扱うためのCollectionView
final class ThumbnailCollectionView: NSCollectionView {
    var onArrowKeyPressed: ((NSEvent.SpecialKey) -> Bool)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let specialKey = event.specialKey,
           (specialKey == .leftArrow || specialKey == .rightArrow),
           onArrowKeyPressed?(specialKey) == true {
            return
        }
        super.keyDown(with: event)
    }
}

/// 画面下部に表示するページサムネイルストリップ
class ThumbnailStripView: NSView {

    // MARK: - 公開インターフェース

    /// セルが選択されたときに呼ばれるコールバック（0始まりの実インデックス）
    var onPageSelected: ((Int) -> Void)?

    /// ドラッグハンドルがドラッグされたときに呼ばれるコールバック（deltaY: 正=上方向=ストリップが高くなる）
    var onResizeDragged: ((CGFloat) -> Void)?

    /// ドラッグ終了時に呼ばれるコールバック（高さ保存用）
    var onResizeDragEnded: (() -> Void)?

    /// 右綴じ（右→左方向）かどうか。trueの場合サムネイルを逆順に表示する
    var isRightToLeft: Bool = false {
        didSet {
            guard oldValue != isRightToLeft else { return }
            updateSectionInsetsForReadingDirection()
            collectionView.reloadData()
        }
    }

    /// tiny画像の取得元（ImageManagerが準拠し、メイン表示プレースホルダとキャッシュを共有する）
    weak var thumbnailProvider: ThumbnailImageProviding?

    /// フォーカス取得のためにinternalアクセスを許可
    private(set) var collectionView: NSCollectionView!

    // MARK: - 非公開

    private let resizeHandle: ThumbnailResizeHandle
    private let scrollView: NSScrollView
    private var itemCount: Int = 0
    /// configure / reloadThumbnails のたびにインクリメントし、古い世代のデコード結果を破棄する
    private var generation: Int = 0
    /// 直近の可視表示インデックス範囲（メインスレッドで更新したスナップショット）
    private var visibleDisplayIndexRange: Range<Int> = 0..<0
    /// 可視範囲外デコードをスキップする際のバッファ件数
    private let visibleRangeBuffer = 8
    private var pendingVisibilityIndexPaths: Set<IndexPath> = []
    private let baseHorizontalSectionInset: CGFloat = 8

    /// プログラム側からの選択変更中はコールバックを抑制する
    private var isUpdatingSelectionProgrammatically = false
    /// プログラム側で設定した選択セットに一致する遅延イベントを抑制する
    private var pendingProgrammaticSelectionIndexPaths: Set<IndexPath> = []

    // MARK: - 初期化

    override init(frame frameRect: NSRect) {
        resizeHandle = ThumbnailResizeHandle()
        scrollView = NSScrollView()
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        resizeHandle = ThumbnailResizeHandle()
        scrollView = NSScrollView()
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // NSCollectionViewFlowLayout（横並び）
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 56, height: 68)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = NSEdgeInsets(top: 0, left: baseHorizontalSectionInset, bottom: 0, right: baseHorizontalSectionInset)

        let thumbnailCollectionView = ThumbnailCollectionView()
        thumbnailCollectionView.onArrowKeyPressed = { [weak self] specialKey in
            self?.handleArrowKeyNavigation(specialKey) ?? false
        }
        collectionView = thumbnailCollectionView
        collectionView.collectionViewLayout = layout
        collectionView.allowsEmptySelection = false
        collectionView.allowsMultipleSelection = true
        collectionView.isSelectable = true
        collectionView.backgroundColors = [.clear]
        // サムネイル並びは isRightToLeft のみで制御し、環境レイアウト方向の自動ミラーを避ける
        collectionView.userInterfaceLayoutDirection = .leftToRight
        collectionView.register(ThumbnailCollectionViewItem.self,
                                forItemWithIdentifier: ThumbnailCollectionViewItem.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self

        scrollView.documentView = collectionView
        scrollView.userInterfaceLayoutDirection = .leftToRight
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // ドラッグリサイズハンドルを上端に追加
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.onResizeDragged = { [weak self] delta in
            self?.onResizeDragged?(delta)
        }
        resizeHandle.onResizeDragEnded = { [weak self] in
            self?.onResizeDragEnded?()
        }
        addSubview(resizeHandle)

        NSLayoutConstraint.activate([
            // ハンドルを上端（imageViewとの境界）に配置
            resizeHandle.topAnchor.constraint(equalTo: topAnchor),
            resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.heightAnchor.constraint(equalToConstant: 6),
            // スクロールビューはハンドルの下
            scrollView.topAnchor.constraint(equalTo: resizeHandle.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - レイアウト

    override func layout() {
        super.layout()
        updateCollectionViewItemSize()
        applyPendingSelectionVisibility(retriesLeft: 0)
        refreshVisibleThumbnails()
    }

    /// ストリップ高さに合わせてコレクションビューのアイテムサイズを更新する
    private func updateCollectionViewItemSize() {
        guard let layout = collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        // handle(6pt) + 上下パディング(14pt) を引いてアイテム高さを算出（元の設計: 88-20=68pt）
        let itemHeight = max(40, bounds.height - 20)
        let itemWidth = max(40, round(itemHeight * 56.0 / 68.0))
        let newSize = NSSize(width: itemWidth, height: itemHeight)
        if layout.itemSize != newSize {
            layout.itemSize = newSize
            layout.invalidateLayout()
        }
        updateSectionInsetsForReadingDirection()
        syncCollectionViewFrameToContent()
    }

    private func updateSectionInsetsForReadingDirection() {
        guard let layout = collectionView?.collectionViewLayout as? NSCollectionViewFlowLayout else { return }

        let topInset = layout.sectionInset.top
        let bottomInset = layout.sectionInset.bottom
        let rightInset = baseHorizontalSectionInset

        let itemCountFloat = CGFloat(itemCount)
        let spacingCount = max(0, itemCount - 1)
        let totalItemWidth = itemCountFloat * layout.itemSize.width
        let totalSpacingWidth = CGFloat(spacingCount) * layout.minimumInteritemSpacing
        let minimumContentWidth = totalItemWidth + totalSpacingWidth + baseHorizontalSectionInset + rightInset
        let viewportWidth = max(0, scrollView.contentView.bounds.width)
        let extraLeadingSpace = max(0, viewportWidth - minimumContentWidth)
        let leftInset = isRightToLeft ? baseHorizontalSectionInset + extraLeadingSpace : baseHorizontalSectionInset

        let currentInset = layout.sectionInset
        let hasInsetChanged = abs(currentInset.left - leftInset) > 0.5
            || abs(currentInset.right - rightInset) > 0.5
            || abs(currentInset.top - topInset) > 0.5
            || abs(currentInset.bottom - bottomInset) > 0.5
        guard hasInsetChanged else { return }

        layout.sectionInset = NSEdgeInsets(top: topInset, left: leftInset, bottom: bottomInset, right: rightInset)
        layout.invalidateLayout()
    }

    // MARK: - インデックス変換

    /// 実インデックス（0始まりのページ番号）→ 表示インデックス（CollectionView上の位置）
    private func displayIndex(for realIndex: Int) -> Int {
        isRightToLeft ? (itemCount - 1 - realIndex) : realIndex
    }

    /// 表示インデックス → 実インデックス
    private func realIndex(for displayIndex: Int) -> Int {
        isRightToLeft ? (itemCount - 1 - displayIndex) : displayIndex
    }

    // MARK: - 公開メソッド

    /// 表示対象の件数を設定し、サムネイルの非同期読み込みを開始する
    func configure(itemCount: Int) {
        self.itemCount = itemCount
        generation += 1
        pendingVisibilityIndexPaths.removeAll()
        visibleDisplayIndexRange = 0..<0
        updateSectionInsetsForReadingDirection()
        collectionView.reloadData()
    }

    /// 指定実インデックスのセルを選択状態にし、必要なら可視領域にスクロールする
    func selectItem(at realIdx: Int, scrollToVisible: Bool) {
        selectItems(at: [realIdx], primaryRealIndex: realIdx, scrollToVisible: scrollToVisible)
    }

    /// 指定実インデックス群のセルを選択状態にし、必要なら可視領域へスクロールする
    func selectItems(at realIndices: [Int], primaryRealIndex: Int?, scrollToVisible: Bool) {
        var seen = Set<Int>()
        let validRealIndices = realIndices.filter { realIdx in
            guard realIdx >= 0 && realIdx < itemCount else { return false }
            return seen.insert(realIdx).inserted
        }
        guard !validRealIndices.isEmpty else { return }

        let displayIndices = validRealIndices.map { displayIndex(for: $0) }
        let indexPaths = Set(displayIndices.map { IndexPath(item: $0, section: 0) })
        let primaryDisplayIndex: Int
        if let primaryRealIndex, primaryRealIndex >= 0, primaryRealIndex < itemCount {
            primaryDisplayIndex = displayIndex(for: primaryRealIndex)
        } else {
            primaryDisplayIndex = displayIndices[0]
        }
        let primaryIndexPath = IndexPath(item: primaryDisplayIndex, section: 0)
        updateSelection(indexPaths: indexPaths, primaryIndexPath: primaryIndexPath, scrollToVisible: scrollToVisible, shouldNotify: false)
    }

    /// サムネイルリストへフォーカスを移す
    @discardableResult
    func focusCollectionView() -> Bool {
        window?.makeFirstResponder(collectionView) ?? false
    }

    /// サムネイルストリップの高さ変更後に呼ぶ。キャッシュは破棄せず、旧サイズのサムネイルを
    /// 表示したまま新サイズのデコードを背後で進め、完了次第差し替える
    func reloadThumbnails() {
        generation += 1
        // 現在の選択を実インデックスで保存（見開き時の複数選択を維持）
        let selectedDisplayIndices = collectionView.selectionIndexPaths.map(\.item).sorted()
        let selectedRealIndices = selectedDisplayIndices.map { realIndex(for: $0) }
        let primaryRealIndex = selectedRealIndices.first
        collectionView.reloadData()
        // reloadData() 後はレイアウト完了を待ってから選択・スクロールを復元する
        if !selectedRealIndices.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.selectItems(at: selectedRealIndices, primaryRealIndex: primaryRealIndex, scrollToVisible: true)
            }
        }
    }

    // MARK: - サムネイル読み込み

    private func loadThumbnail(at realIdx: Int) {
        guard realIdx < itemCount else { return }

        // アイテム高さと画面スケールからサムネイル解像度を決定（Retina対応）
        let itemHeight = (collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize.height ?? 68
        let scale = window?.backingScaleFactor ?? 2.0
        let maxPixelSize = max(120, Int(itemHeight * scale))

        let displayIdx = displayIndex(for: realIdx)
        let captureGeneration = generation
        let range = expandedVisibleRange(buffer: visibleRangeBuffer)

        // tinyティアキャッシュ（ImageManagerと共有）からデコードを依頼する。
        // 可視範囲外（バッファ含む）ならデコードをスキップする（再可視化時に再度呼ばれる）
        thumbnailProvider?.requestTinyImage(
            at: realIdx,
            maxPixelSize: maxPixelSize,
            isStillNeeded: { range.contains(displayIdx) }
        ) { [weak self] index, image in
            guard let self, self.generation == captureGeneration, let image else { return }
            let indexPath = IndexPath(item: self.displayIndex(for: index), section: 0)
            if let item = self.collectionView.item(at: indexPath) as? ThumbnailCollectionViewItem {
                item.configure(image: image)
            }
        }
    }

    /// 可視セルのうちサムネイル未取得・サイズ不一致のものを再デコードする
    private func refreshVisibleThumbnails() {
        updateVisibleDisplayIndexRange()
        for indexPath in collectionView.indexPathsForVisibleItems() {
            loadThumbnail(at: realIndex(for: indexPath.item))
        }
    }

    /// 直近の可視表示インデックス範囲を更新する
    private func updateVisibleDisplayIndexRange() {
        let visibleItems = collectionView.indexPathsForVisibleItems().map(\.item)
        guard let minItem = visibleItems.min(), let maxItem = visibleItems.max() else { return }
        visibleDisplayIndexRange = minItem..<(maxItem + 1)
    }

    /// 可視範囲をバッファ分拡張した表示インデックス範囲を返す
    private func expandedVisibleRange(buffer: Int) -> Range<Int> {
        let lower = max(0, visibleDisplayIndexRange.lowerBound - buffer)
        let upper = min(itemCount, visibleDisplayIndexRange.upperBound + buffer)
        guard lower < upper else { return 0..<0 }
        return lower..<upper
    }

    // MARK: - キーボードナビゲーション

    private func handleArrowKeyNavigation(_ specialKey: NSEvent.SpecialKey) -> Bool {
        guard itemCount > 0 else { return true }

        let currentDisplayIndex = collectionView.selectionIndexPaths.first?.item ?? displayIndex(for: 0)
        let step: Int
        switch specialKey {
        case .leftArrow:
            step = -1
        case .rightArrow:
            step = 1
        default:
            return false
        }

        let nextDisplayIndex = max(0, min(itemCount - 1, currentDisplayIndex + step))
        guard nextDisplayIndex != currentDisplayIndex else { return true }
        updateSelection(displayIndex: nextDisplayIndex, scrollToVisible: true, shouldNotify: true)
        return true
    }

    private func updateSelection(displayIndex: Int, scrollToVisible: Bool, shouldNotify: Bool) {
        guard displayIndex >= 0 && displayIndex < itemCount else { return }
        let indexPath = IndexPath(item: displayIndex, section: 0)
        updateSelection(indexPaths: [indexPath], primaryIndexPath: indexPath, scrollToVisible: scrollToVisible, shouldNotify: shouldNotify)
    }

    private func updateSelection(indexPaths: Set<IndexPath>,
                                 primaryIndexPath: IndexPath,
                                 scrollToVisible: Bool,
                                 shouldNotify: Bool) {
        guard !indexPaths.isEmpty else { return }
        guard primaryIndexPath.item >= 0 && primaryIndexPath.item < itemCount else { return }

        if shouldNotify {
            pendingProgrammaticSelectionIndexPaths.removeAll()
        } else {
            pendingProgrammaticSelectionIndexPaths = indexPaths
        }

        isUpdatingSelectionProgrammatically = true
        let previousSelection = collectionView.selectionIndexPaths
        if !previousSelection.isEmpty {
            collectionView.deselectItems(at: previousSelection)
        }
        collectionView.selectItems(at: indexPaths, scrollPosition: [])
        isUpdatingSelectionProgrammatically = false

        if scrollToVisible {
            pendingVisibilityIndexPaths = indexPaths
            applyPendingSelectionVisibility(retriesLeft: 6)
        } else {
            pendingVisibilityIndexPaths.removeAll()
        }

        if shouldNotify {
            onPageSelected?(realIndex(for: primaryIndexPath.item))
        }
    }

    private func applyPendingSelectionVisibility(retriesLeft: Int) {
        guard !pendingVisibilityIndexPaths.isEmpty else { return }
        let validIndexPaths = pendingVisibilityIndexPaths.filter { indexPath in
            indexPath.item >= 0 && indexPath.item < itemCount
        }
        guard !validIndexPaths.isEmpty else {
            pendingVisibilityIndexPaths.removeAll()
            return
        }
        pendingVisibilityIndexPaths = Set(validIndexPaths)

        collectionView.layoutSubtreeIfNeeded()
        syncCollectionViewFrameToContent()
        let itemFrames = validIndexPaths.compactMap { itemFrameForIndexPath($0) }
        guard itemFrames.count == validIndexPaths.count else {
            scheduleSelectionVisibilityRetry(retriesLeft: retriesLeft)
            return
        }
        guard let targetFrame = unionFrame(for: itemFrames) else {
            pendingVisibilityIndexPaths.removeAll()
            return
        }

        scrollItemFrameToVisible(targetFrame)
        if areAllItemFramesVisible(itemFrames) {
            pendingVisibilityIndexPaths.removeAll()
            return
        }
        scheduleSelectionVisibilityRetry(retriesLeft: retriesLeft)
    }

    private func scheduleSelectionVisibilityRetry(retriesLeft: Int) {
        guard retriesLeft > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyPendingSelectionVisibility(retriesLeft: retriesLeft - 1)
        }
    }

    private func itemFrameForIndexPath(_ indexPath: IndexPath) -> NSRect? {
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
        return attributes.frame
    }

    private func scrollItemFrameToVisible(_ itemFrame: NSRect) {
        let clipView = scrollView.contentView
        var visibleRect = clipView.bounds
        guard visibleRect.width > 0 else { return }

        let leadingPadding: CGFloat = 4
        let trailingPadding: CGFloat = 4
        let targetMinX = itemFrame.minX - leadingPadding
        let targetMaxX = itemFrame.maxX + trailingPadding

        var targetOffsetX = visibleRect.origin.x
        if targetMinX < visibleRect.minX {
            targetOffsetX = targetMinX
        } else if targetMaxX > visibleRect.maxX {
            targetOffsetX = targetMaxX - visibleRect.width
        }

        let maxOffsetX = max(0, collectionView.bounds.width - visibleRect.width)
        targetOffsetX = min(max(0, targetOffsetX), maxOffsetX)
        guard abs(targetOffsetX - visibleRect.origin.x) > 0.5 else { return }

        visibleRect.origin.x = targetOffsetX
        clipView.scroll(to: visibleRect.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func isItemFrameVisible(_ itemFrame: NSRect) -> Bool {
        let visibleRect = scrollView.contentView.bounds.insetBy(dx: -1, dy: -1)
        return visibleRect.minX <= itemFrame.minX && visibleRect.maxX >= itemFrame.maxX
    }

    private func areAllItemFramesVisible(_ itemFrames: [NSRect]) -> Bool {
        itemFrames.allSatisfy { isItemFrameVisible($0) }
    }

    private func unionFrame(for itemFrames: [NSRect]) -> NSRect? {
        guard let firstFrame = itemFrames.first else { return nil }
        return itemFrames.dropFirst().reduce(firstFrame) { partial, frame in
            partial.union(frame)
        }
    }

    private func syncCollectionViewFrameToContent() {
        guard let layout = collectionView.collectionViewLayout else { return }
        let contentSize = layout.collectionViewContentSize
        let viewportSize = scrollView.contentView.bounds.size
        let targetSize = NSSize(
            width: max(contentSize.width, viewportSize.width),
            height: max(contentSize.height, viewportSize.height)
        )
        guard collectionView.frame.size != targetSize else { return }
        var frame = collectionView.frame
        frame.origin = .zero
        frame.size = targetSize
        collectionView.frame = frame
    }
}

// MARK: - NSCollectionViewDataSource

extension ThumbnailStripView: NSCollectionViewDataSource {

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        itemCount
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ThumbnailCollectionViewItem.identifier,
                                          for: indexPath) as! ThumbnailCollectionViewItem
        let rIdx = realIndex(for: indexPath.item)
        updateVisibleDisplayIndexRange()
        item.configure(image: thumbnailProvider?.cachedTinyImage(at: rIdx))
        loadThumbnail(at: rIdx)
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension ThumbnailStripView: NSCollectionViewDelegate {

    func collectionView(_ collectionView: NSCollectionView,
                        shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        guard !isUpdatingSelectionProgrammatically else { return indexPaths }
        guard let firstIndexPath = indexPaths.sorted(by: { $0.item < $1.item }).first else { return [] }
        return [firstIndexPath]
    }

    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isUpdatingSelectionProgrammatically else { return }
        if !pendingProgrammaticSelectionIndexPaths.isEmpty,
           collectionView.selectionIndexPaths == pendingProgrammaticSelectionIndexPaths {
            pendingProgrammaticSelectionIndexPaths.removeAll()
            return
        }
        pendingProgrammaticSelectionIndexPaths.removeAll()
        guard let indexPath = indexPaths.sorted(by: { $0.item < $1.item }).first else { return }
        onPageSelected?(realIndex(for: indexPath.item))
    }
}

//
//  ThumbnailStripView.swift
//  coverZipViewer
//

import Cocoa
import ImageIO

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

    // MARK: - Public interface

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
            collectionView.reloadData()
        }
    }

    /// フォーカス取得のためにinternalアクセスを許可
    private(set) var collectionView: NSCollectionView!

    // MARK: - Private

    private let resizeHandle: ThumbnailResizeHandle
    private let scrollView: NSScrollView
    private var entries: [CZImageEntryInfo] = []
    private var zipData: Data?
    private var thumbnailCache: [Int: NSImage] = [:]
    private let decodeQueue = DispatchQueue(label: "com.dmng.coverzip.thumbnail", qos: .utility, attributes: .concurrent)
    private var pendingVisibilityIndexPath: IndexPath?

    /// プログラム側からの選択変更中はコールバックを抑制する
    private var isUpdatingSelectionProgrammatically = false

    // MARK: - Initialization

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
        layout.sectionInset = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)

        let thumbnailCollectionView = ThumbnailCollectionView()
        thumbnailCollectionView.onArrowKeyPressed = { [weak self] specialKey in
            self?.handleArrowKeyNavigation(specialKey) ?? false
        }
        collectionView = thumbnailCollectionView
        collectionView.collectionViewLayout = layout
        collectionView.allowsEmptySelection = false
        collectionView.allowsMultipleSelection = false
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

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateCollectionViewItemSize()
        applyPendingSelectionVisibility(retriesLeft: 0)
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
        syncCollectionViewFrameToContent()
    }

    // MARK: - Index conversion

    /// 実インデックス（0始まりのページ番号）→ 表示インデックス（CollectionView上の位置）
    private func displayIndex(for realIndex: Int) -> Int {
        isRightToLeft ? (entries.count - 1 - realIndex) : realIndex
    }

    /// 表示インデックス → 実インデックス
    private func realIndex(for displayIndex: Int) -> Int {
        isRightToLeft ? (entries.count - 1 - displayIndex) : displayIndex
    }

    // MARK: - Public methods

    /// ZIPデータとエントリー情報を設定し、サムネイルの非同期読み込みを開始する
    func configure(zipData: Data, entries: [CZImageEntryInfo]) {
        self.zipData = zipData
        self.entries = entries
        pendingVisibilityIndexPath = nil
        thumbnailCache.removeAll()
        collectionView.reloadData()
    }

    /// 指定実インデックスのセルを選択状態にし、必要なら可視領域にスクロールする
    func selectItem(at realIdx: Int, scrollToVisible: Bool) {
        guard realIdx >= 0 && realIdx < entries.count else { return }
        let displayIdx = displayIndex(for: realIdx)
        updateSelection(displayIndex: displayIdx, scrollToVisible: scrollToVisible, shouldNotify: false)
    }

    /// サムネイルリストへフォーカスを移す
    @discardableResult
    func focusCollectionView() -> Bool {
        window?.makeFirstResponder(collectionView) ?? false
    }

    /// サムネイルキャッシュをクリアして再ロードする（ストリップ高さ変更後に呼ぶ）
    func reloadThumbnails() {
        // 現在の選択を実インデックスで保存
        let selectedRealIndex = collectionView.selectionIndexPaths.first.map { realIndex(for: $0.item) }
        thumbnailCache.removeAll()
        collectionView.reloadData()
        // reloadData() 後はレイアウト完了を待ってから選択・スクロールを復元する
        if let realIdx = selectedRealIndex {
            DispatchQueue.main.async { [weak self] in
                self?.selectItem(at: realIdx, scrollToVisible: true)
            }
        }
    }

    // MARK: - Thumbnail loading

    private func loadThumbnail(at realIdx: Int) {
        guard thumbnailCache[realIdx] == nil,
              let zipData = zipData,
              realIdx < entries.count else { return }

        let entry = entries[realIdx]
        // アイテム高さと画面スケールからサムネイル解像度を決定（Retina対応）
        let itemHeight = (collectionView.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize.height ?? 68
        let scale = window?.backingScaleFactor ?? 2.0
        let maxPixelSize = max(120, Int(itemHeight * scale))
        decodeQueue.async { [weak self] in
            guard let self else { return }
            guard let imageData = CZZip.extractImageData(from: zipData, entryInfo: entry) else { return }
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return }

            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
            let image = NSImage(cgImage: cgImage, size: .zero)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.thumbnailCache[realIdx] = image
                let dispIdx = self.displayIndex(for: realIdx)
                let indexPath = IndexPath(item: dispIdx, section: 0)
                if let item = self.collectionView.item(at: indexPath) as? ThumbnailCollectionViewItem {
                    item.configure(image: image)
                }
            }
        }
    }

    // MARK: - Keyboard navigation

    private func handleArrowKeyNavigation(_ specialKey: NSEvent.SpecialKey) -> Bool {
        guard !entries.isEmpty else { return true }

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

        let nextDisplayIndex = max(0, min(entries.count - 1, currentDisplayIndex + step))
        guard nextDisplayIndex != currentDisplayIndex else { return true }
        updateSelection(displayIndex: nextDisplayIndex, scrollToVisible: true, shouldNotify: true)
        return true
    }

    private func updateSelection(displayIndex: Int, scrollToVisible: Bool, shouldNotify: Bool) {
        guard displayIndex >= 0 && displayIndex < entries.count else { return }
        let indexPath = IndexPath(item: displayIndex, section: 0)

        isUpdatingSelectionProgrammatically = true
        let previousSelection = collectionView.selectionIndexPaths
        if !previousSelection.isEmpty {
            collectionView.deselectItems(at: previousSelection)
        }
        collectionView.selectItems(at: [indexPath], scrollPosition: [])
        isUpdatingSelectionProgrammatically = false

        if scrollToVisible {
            pendingVisibilityIndexPath = indexPath
            applyPendingSelectionVisibility(retriesLeft: 6)
        }

        if shouldNotify {
            onPageSelected?(realIndex(for: displayIndex))
        }
    }

    private func applyPendingSelectionVisibility(retriesLeft: Int) {
        guard let indexPath = pendingVisibilityIndexPath else { return }
        guard indexPath.item >= 0 && indexPath.item < entries.count else {
            pendingVisibilityIndexPath = nil
            return
        }

        collectionView.layoutSubtreeIfNeeded()
        syncCollectionViewFrameToContent()
        guard let itemFrame = itemFrameForIndexPath(indexPath) else {
            scheduleSelectionVisibilityRetry(retriesLeft: retriesLeft)
            return
        }

        scrollItemFrameToVisible(itemFrame)
        if isItemFrameVisible(itemFrame) {
            pendingVisibilityIndexPath = nil
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
        entries.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ThumbnailCollectionViewItem.identifier,
                                          for: indexPath) as! ThumbnailCollectionViewItem
        let rIdx = realIndex(for: indexPath.item)
        item.configure(image: thumbnailCache[rIdx])
        loadThumbnail(at: rIdx)
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension ThumbnailStripView: NSCollectionViewDelegate {

    func collectionView(_ collectionView: NSCollectionView,
                        didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isUpdatingSelectionProgrammatically else { return }
        guard let indexPath = indexPaths.first else { return }
        onPageSelected?(realIndex(for: indexPath.item))
    }
}

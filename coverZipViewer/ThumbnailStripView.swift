//
//  ThumbnailStripView.swift
//  coverZipViewer
//

import Cocoa
import ImageIO

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

    private let scrollView: NSScrollView
    private var entries: [CZImageEntryInfo] = []
    private var zipData: Data?
    private var thumbnailCache: [Int: NSImage] = [:]
    private let decodeQueue = DispatchQueue(label: "com.dmng.coverzip.thumbnail", qos: .utility, attributes: .concurrent)

    /// プログラム側からの選択変更中はコールバックを抑制する
    private var isUpdatingSelectionProgrammatically = false

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        scrollView = NSScrollView()
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
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
        collectionView.register(ThumbnailCollectionViewItem.self,
                                forItemWithIdentifier: ThumbnailCollectionViewItem.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
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

    // MARK: - Thumbnail loading

    private func loadThumbnail(at realIdx: Int) {
        guard thumbnailCache[realIdx] == nil,
              let zipData = zipData,
              realIdx < entries.count else { return }

        let entry = entries[realIdx]
        decodeQueue.async { [weak self] in
            guard let self else { return }
            guard let imageData = CZZip.extractImageData(from: zipData, entryInfo: entry) else { return }
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return }

            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: 120,
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
        collectionView.selectItems(at: [indexPath], scrollPosition: scrollToVisible ? .nearestHorizontalEdge : [])
        isUpdatingSelectionProgrammatically = false

        if shouldNotify {
            onPageSelected?(realIndex(for: displayIndex))
        }
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

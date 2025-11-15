//
//  ImageManager.swift
//  coverZipViewer
//
//  Created by Nihondo on 2025/08/24.
//

import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreServices
// Shared utilities are provided in Shared/* files

// ZIPの低レベル処理はShared/ZipCoreに集約

/**
 * プレビュー用の画像管理クラス
 * ZIPファイル内の画像リストを管理し、ページング機能を提供する
 * 遅延ロードによりメモリ効率と初期表示速度を最適化
 */
class ImageManager {

    // 遅延ロード用のメタデータとZIPデータ
    private var imageEntryInfos: [CZImageEntryInfo] = []
    private var zipData: Data?
    private var currentIndex: Int = 0
    private var imageCache: [Int: NSImage] = [:]
    private let maxCacheSize: Int = 10
    private var pendingPreloadTasks: [Int: DispatchWorkItem] = [:]
    private var pendingHighResTasks: [Int: DispatchWorkItem] = [:]
    private let preloadQueue = DispatchQueue(label: "com.dmng.CoverZip.imagePreload", qos: .userInitiated)
    private var memoryPressureObserver: NSObjectProtocol?
    // 見開きの左右組み合わせを1ページ分ずらすためのオフセット（0 or 1）
    private var spreadPairOffset: Int = 0

    // リサイズ画像キャッシュ（サイズ別）
    private var resizedImageCache: [String: NSImage] = [:]
    private let maxResizedCacheSize: Int = 20
    private var targetDisplaySize: NSSize = NSSize.zero
    private let downsampleOverscanRatio: CGFloat = 1.2
    private let fallbackMaxDisplayPixels: Int = 3840
    private let incrementalPreviewChunkBytes: Int = 256 * 1024
    private let incrementalPreviewMinPixels: Int = 720
    private var preloadPreference: PreloadPreference = .single
    private var pendingPreloadChunks: [[Int]] = []
    // デコードキャッシュ方針（設定から取得、デフォルトは .deferred）
    private var decodeCachePolicy: CZImageDecodeCachePolicy { AppSettings.shared.imageDecodeCachePolicy }
    // 全画像のバックグラウンド読み込み中かどうか（常にfalseになる：遅延ロードのため）
    private(set) var isLoadingAll: Bool = false
    
    /**
     * 表示対象サイズを設定（パフォーマンス最適化用）
     * 
     * @param size 表示対象の最大サイズ（ウィンドウサイズ等）
     */
    func setTargetDisplaySize(_ size: NSSize) {
        guard size.width > 0 && size.height > 0 else { return }
        
        if targetDisplaySize != size {
            targetDisplaySize = size
            // サイズが変わったらリサイズキャッシュをクリア
            resizedImageCache.removeAll()
            NSLog("[ImageManager] Target display size updated to \(Int(size.width))x\(Int(size.height))")
        }
    }

    func setPreloadPreference(_ preference: PreloadPreference) {
        guard preloadPreference != preference else { return }
        preloadPreference = preference
        if hasImages() {
            preloadAdjacentImages()
        }
    }
    
    /**
     * ZIPファイルから画像を読み込む（遅延ロード方式）
     *
     * メタデータを即座に取得し、画像データは必要時にロード
     * これにより2ページ目以降へのページ送りが即座に可能になる
     *
     * @param url ZIPファイルのURL
     * @return 読み込み成功時はtrue、失敗時はfalse
     */
    func loadImages(from url: URL) -> Bool {
        do {
            cancelAllBackgroundTasks()
            // ZIPデータをメモリにマップ（遅延ロード用）
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            self.zipData = data

            // 画像エントリのメタデータを即座に取得（高速）
            let entryInfos = CZZip.imageEntryInfoList(from: data)
            guard !entryInfos.isEmpty else { return false }

            // メタデータを設定（ページ送りが即座に可能になる）
            self.imageEntryInfos = entryInfos
            self.currentIndex = 0
            self.imageCache.removeAll()
            self.resizedImageCache.removeAll()
            setupMemoryPressureMonitoring()

            // 1ページ目を即座にキャッシュ（表示高速化）
            _ = getImageAtIndex(0)

            // 隣接ページのプリロード
            preloadAdjacentImages()

            NSLog("[ImageManager] Loaded %d images (lazy mode)", entryInfos.count)
            return true

        } catch {
            NSLog("[ImageManager] Failed to load ZIP: \(error)")
            return false
        }
    }
    
    /**
     * 現在の画像を取得する
     *
     * @return 現在の画像データ（画像がない場合はnil）
     */
    func getCurrentImage() -> NSImage? {
        return getImageAtIndex(currentIndex)
    }
    
    /**
     * 見開き用の画像を取得する（左右2ページ）
     *
     * @param isRightToLeft 右から左読み（日本語）の場合はtrue
     * @return (左ページ画像, 右ページ画像)のタプル。片方がない場合はnilが入る
     */
    func getSpreadImages(isRightToLeft: Bool) -> (left: NSImage?, right: NSImage?) {
        guard !imageEntryInfos.isEmpty else {
            return (nil, nil)
        }
        
        // 表紙（1ページ目）は常に単ページ
        if currentIndex == 0 {
            return (getCurrentImage(), nil)
        }
        
        let leftIndex: Int
        let rightIndex: Int
        // ペア判定の偶奇を、オフセットで反転可能にする
        let parity = (currentIndex + spreadPairOffset) % 2
        
        if isRightToLeft {
            // RTL: 左3-右2, 左5-右4...（奇数ページが左）
            if parity == 1 {
                // 偶数ページ（2, 4, 6...）の場合、右側に配置し、左側は次のページ
                leftIndex = currentIndex + 1
                rightIndex = currentIndex
            } else {
                // 奇数ページ（3, 5, 7...）の場合、左側に配置し、右側は前のページ
                leftIndex = currentIndex
                rightIndex = currentIndex - 1
            }
        } else {
            // LTR: 左2-右3, 左4-右5...（偶数ページが左）
            if parity == 1 {
                // 偶数ページ（2, 4, 6...）の場合、左側に配置し、右側は次のページ
                leftIndex = currentIndex
                rightIndex = currentIndex + 1
            } else {
                // 奇数ページ（3, 5, 7...）の場合、右側に配置し、左側は前のページ
                leftIndex = currentIndex - 1
                rightIndex = currentIndex
            }
        }
        
        let leftImage = getImageAtIndex(leftIndex)
        let rightImage = getImageAtIndex(rightIndex)
        
        return (leftImage, rightImage)
    }

    // 現在の見開きペアリングオフセットをトグル（0<->1）
    func toggleSpreadPairOffset() {
        spreadPairOffset = 1 - spreadPairOffset
    }

    func setSpreadPairOffset(_ value: Int) {
        spreadPairOffset = (value % 2 + 2) % 2
    }

    func getSpreadPairOffset() -> Int { spreadPairOffset }
    
    /**
     * 指定されたインデックスの画像を取得する（遅延ロード）
     *
     * @param index 画像のインデックス
     * @return 画像データ（範囲外やエラーの場合はnil）
     */
    private func getImageAtIndex(_ index: Int) -> NSImage? {
        guard index >= 0, index < imageEntryInfos.count else {
            return nil
        }

        // リサイズキャッシュから確認（ターゲットサイズが設定されている場合）
        if targetDisplaySize.width > 0 && targetDisplaySize.height > 0 {
            let cacheKey = "\(index)_\(Int(targetDisplaySize.width))x\(Int(targetDisplaySize.height))"
            if let resizedImage = resizedImageCache[cacheKey] {
                return resizedImage
            }
        }

        // 元画像キャッシュから確認
        if let cachedImage = imageCache[index] {
            // ターゲットサイズが設定されていればリサイズして返す
            if targetDisplaySize.width > 0 && targetDisplaySize.height > 0 {
                if let resizedImage = resizeImageForDisplay(cachedImage, targetSize: targetDisplaySize) {
                    cacheResizedImage(resizedImage, at: index, size: targetDisplaySize)
                    return resizedImage
                }
            }
            return cachedImage
        }

        // ZIPから画像データを遅延ロード
        guard let zipData = zipData else {
            NSLog("[ImageManager] ZIP data not available for lazy loading")
            return nil
        }

        let entryInfo = imageEntryInfos[index]
        guard let imageData = CZZip.extractImageData(from: zipData, entryInfo: entryInfo) else {
            NSLog("[ImageManager] Failed to extract image at index \(index): \(entryInfo.filename)")
            return nil
        }

        guard let image = decodeImage(data: imageData, at: index) else {
            NSLog("[ImageManager] Failed to decode image at index \(index): \(entryInfo.filename)")
            return nil
        }

        // ターゲットサイズが設定されていればリサイズ
        if targetDisplaySize.width > 0 && targetDisplaySize.height > 0 {
            if let resizedImage = resizeImageForDisplay(image, targetSize: targetDisplaySize) {
                cacheResizedImage(resizedImage, at: index, size: targetDisplaySize)
                // 元画像もキャッシュ（メモリに余裕があれば）
                if imageCache.count < maxCacheSize {
                    cacheImage(image, at: index)
                }
                return resizedImage
            }
        }

        cacheImage(image, at: index)
        return image
    }
    
    /**
     * 現在の画像のファイル名を取得する
     *
     * @return 現在の画像のファイル名（画像がない場合は空文字列）
     */
    func getCurrentImageName() -> String {
        guard !imageEntryInfos.isEmpty, currentIndex >= 0, currentIndex < imageEntryInfos.count else {
            return ""
        }

        return imageEntryInfos[currentIndex].filename
    }
    
    /**
     * 次の画像に移動する
     *
     * @param isSpreadMode 見開きモードの場合はtrue
     * @return 移動成功時はtrue、移動できない場合はfalse
     */
    func nextImage(isSpreadMode: Bool = false) -> Bool {
        guard !imageEntryInfos.isEmpty else {
            return false
        }

        if isSpreadMode {
            // 見開きモードでは2ページずつ移動（表紙除く）
            if currentIndex == 0 {
                // 表紙から2ページ目へ
                guard currentIndex < imageEntryInfos.count - 1 else { return false }
                currentIndex = 1
            } else {
                // 2ページずつ進む
                let nextIndex = currentIndex + 2
                guard nextIndex < imageEntryInfos.count else { return false }
                currentIndex = nextIndex
            }
        } else {
            // 単ページモードでは1ページずつ
            guard currentIndex < imageEntryInfos.count - 1 else { return false }
            currentIndex += 1
        }

        preloadAdjacentImages()
        return true
    }

    /**
     * 前の画像に移動する
     *
     * @param isSpreadMode 見開きモードの場合はtrue
     * @return 移動成功時はtrue、移動できない場合はfalse
     */
    func previousImage(isSpreadMode: Bool = false) -> Bool {
        guard !imageEntryInfos.isEmpty, currentIndex > 0 else {
            return false
        }

        if isSpreadMode {
            // 見開きモードでは2ページずつ移動
            if currentIndex == 1 {
                // 2ページ目から表紙へ
                currentIndex = 0
            } else {
                // 2ページずつ戻る
                let prevIndex = currentIndex - 2
                currentIndex = max(0, prevIndex)
            }
        } else {
            // 単ページモードでは1ページずつ
            currentIndex -= 1
        }

        preloadAdjacentImages()
        return true
    }

    /**
     * 画像の総数を取得する
     *
     * @return 画像の総数
     */
    func getImageCount() -> Int {
        return imageEntryInfos.count
    }
    
    /**
     * 現在のページ番号を取得する（1始まり）
     * 
     * @return 現在のページ番号
     */
    func getCurrentPageNumber() -> Int {
        return currentIndex + 1
    }

    func getCurrentIndex() -> Int {
        return currentIndex
    }

    /// 指定ページへ移動（1始まり）
    /// - Parameter page: 1...imageCount の範囲内で移動。範囲外は丸め込み。
    /// - Returns: 有効な画像が存在する場合にtrue
    func goToPage(_ page: Int) -> Bool {
        guard !imageEntryInfos.isEmpty else { return false }
        let clamped = max(1, min(page, imageEntryInfos.count))
        let newIndex = clamped - 1
        currentIndex = newIndex
        preloadAdjacentImages()
        return true
    }

    /**
     * 画像があるかどうかを確認する
     *
     * @return 画像がある場合はtrue、ない場合はfalse
     */
    func hasImages() -> Bool {
        return !imageEntryInfos.isEmpty
    }
    
    /**
     * 現在のページが表紙かどうかを判定する
     * 
     * @return 表紙の場合はtrue、それ以外はfalse
     */
    func isCoverPage() -> Bool {
        return currentIndex == 0
    }
    
    // MARK: - Cache Management Methods
    
    private func cacheImage(_ image: NSImage, at index: Int) {
        if imageCache.count >= maxCacheSize {
            removeOldestCachedImage()
        }
        imageCache[index] = image
    }
    
    private func removeOldestCachedImage() {
        guard !imageCache.isEmpty else { return }
        
        // 現在のインデックスから最も離れているキャッシュを削除
        let farthestIndex = imageCache.keys.max { abs($0 - currentIndex) < abs($1 - currentIndex) }
        if let indexToRemove = farthestIndex {
            imageCache.removeValue(forKey: indexToRemove)
        }
    }
    
    func preloadAdjacentImages() {
        guard hasImages() else { return }
        let plan = buildPreloadPlan()
        NSLog("[ImageManager] Preload plan primary=%@ additional=%@", plan.primaryOffsets.description, plan.additionalChunks.description)
        pendingPreloadChunks = plan.additionalChunks
        schedulePreloadTasks(for: plan.primaryOffsets, cancelOthers: true)
    }

    private func schedulePreloadTasks(for indices: [Int], cancelOthers: Bool) {
        let validIndices = indices.filter {
            $0 >= 0 && $0 < imageEntryInfos.count && imageCache[$0] == nil
        }
        NSLog("[ImageManager] Scheduling preload targets=%@ (cancelOthers=%@)", validIndices.description, String(cancelOthers))
        if cancelOthers {
            let keepSet = Set(validIndices)
            cancelObsoletePreloadTasks(keeping: keepSet)
        }

        for index in validIndices where pendingPreloadTasks[index] == nil {
            let workItem = makePreloadWorkItem(for: index)
            pendingPreloadTasks[index] = workItem
            preloadQueue.async(execute: workItem)
        }
    }

    private func cancelObsoletePreloadTasks(keeping keepSet: Set<Int>) {
        guard !pendingPreloadTasks.isEmpty else { return }
        var removalTargets: [Int] = []
        for (index, workItem) in pendingPreloadTasks where !keepSet.contains(index) {
            workItem.cancel()
            removalTargets.append(index)
        }
        removalTargets.forEach { pendingPreloadTasks.removeValue(forKey: $0) }
    }

    private func makePreloadWorkItem(for index: Int) -> DispatchWorkItem {
        var workItemReference: DispatchWorkItem?
        let workItem = DispatchWorkItem(qos: .userInitiated) { [weak self] in
            guard let self else { return }
            let isCancelled: () -> Bool = { workItemReference?.isCancelled ?? true }
            self.loadImageAtIndex(index, isCancelled: isCancelled)
            self.completePreloadTask(for: index, workItem: workItemReference)
        }
        workItemReference = workItem
        return workItem
    }

    private func completePreloadTask(for index: Int, workItem: DispatchWorkItem?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let current = self.pendingPreloadTasks[index], let workItem, current === workItem {
                self.pendingPreloadTasks.removeValue(forKey: index)
            }
            self.scheduleNextPreloadChunkIfNeeded()
        }
    }

    private func scheduleNextPreloadChunkIfNeeded() {
        guard pendingPreloadTasks.isEmpty, !pendingPreloadChunks.isEmpty else { return }
        let nextOffsets = pendingPreloadChunks.removeFirst()
        NSLog("[ImageManager] Scheduling next preload chunk=%@", nextOffsets.description)
        schedulePreloadTasks(for: nextOffsets, cancelOthers: false)
    }

    private func buildPreloadPlan() -> PreloadPlan {
        switch preloadPreference {
        case .single:
            return PreloadPlan(
                primaryOffsets: [currentIndex - 1, currentIndex + 1],
                additionalChunks: [
                    [currentIndex - 2, currentIndex + 2],
                    [currentIndex - 3, currentIndex + 3]
                ]
            )
        case .spread:
            return PreloadPlan(
                primaryOffsets: [currentIndex - 2, currentIndex - 1, currentIndex + 1, currentIndex + 2],
                additionalChunks: [
                    [currentIndex - 4, currentIndex - 3, currentIndex + 3, currentIndex + 4]
                ]
            )
        }
    }

    private func loadImageAtIndex(_ index: Int, isCancelled: (() -> Bool)?) {
        guard index >= 0, index < imageEntryInfos.count else { return }
        guard isCancelled?() != true else { return }
        if imageCache[index] != nil { return }

        guard let zipData = zipData else { return }
        guard isCancelled?() != true else { return }

        let entryInfo = imageEntryInfos[index]
        guard let imageData = CZZip.extractImageData(from: zipData, entryInfo: entryInfo) else {
            return
        }
        guard isCancelled?() != true else { return }

        if let image = decodeImage(data: imageData, at: index) {
            guard isCancelled?() != true else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.imageCache[index] == nil {
                    self.cacheImage(image, at: index)
                    NSLog("[ImageManager] Preload completed index=%d", index)
                }
            }
        }
    }
    
    // MARK: - Memory Management Methods
    
    private func setupMemoryPressureMonitoring() {
        removeMemoryPressureObserver()
        
        // App ExtensionではNSApplicationの通知を使用できないため、シンプルなキャッシュサイズ制限のみ実装
        // 必要に応じて、メモリ使用量を手動で監視する実装も可能
    }
    
    private func removeMemoryPressureObserver() {
        if let observer = memoryPressureObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryPressureObserver = nil
        }
    }
    
    private func handleMemoryPressure() {
        // 現在の画像以外のキャッシュをクリア
        let currentImage = imageCache[currentIndex]
        imageCache.removeAll()
        
        if let image = currentImage {
            imageCache[currentIndex] = image
        }
    }
    
    func clearCache() {
        let currentImage = imageCache[currentIndex]
        imageCache.removeAll()
        resizedImageCache.removeAll()
        cancelAllBackgroundTasks()
        
        if let image = currentImage {
            imageCache[currentIndex] = image
        }
        NSLog("[ImageManager] All image cache cleared")
    }

    private func cancelAllBackgroundTasks() {
        for (_, task) in pendingPreloadTasks { task.cancel() }
        pendingPreloadTasks.removeAll()
        for (_, task) in pendingHighResTasks { task.cancel() }
        pendingHighResTasks.removeAll()
    }
    
    // MARK: - Image Resizing Methods
    
    /**
     * 表示用に画像をリサイズする
     */
    private func resizeImageForDisplay(_ image: NSImage, targetSize: NSSize) -> NSImage? {
        let originalSize = image.size
        
        // リサイズが不要な場合はそのまま返す
        if originalSize.width <= targetSize.width && originalSize.height <= targetSize.height {
            return image
        }
        
        // アスペクト比を維持してリサイズ
        let scale = min(targetSize.width / originalSize.width, targetSize.height / originalSize.height)
        let newSize = NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
        
        // 高品質リサイズ
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        
        let context = NSGraphicsContext.current?.cgContext
        context?.interpolationQuality = .high
        
        let rect = NSRect(origin: .zero, size: newSize)
        image.draw(in: rect, from: NSRect(origin: .zero, size: originalSize), operation: .copy, fraction: 1.0)
        
        resizedImage.unlockFocus()
        
        NSLog("[ImageManager] Resized image from \(Int(originalSize.width))x\(Int(originalSize.height)) to \(Int(newSize.width))x\(Int(newSize.height))")
        return resizedImage
    }
    
    /**
     * リサイズ画像をキャッシュに追加
     */
    private func cacheResizedImage(_ image: NSImage, at index: Int, size: NSSize) {
        let cacheKey = "\(index)_\(Int(size.width))x\(Int(size.height))"
        
        // キャッシュサイズ制限チェック
        if resizedImageCache.count >= maxResizedCacheSize {
            removeOldestResizedCachedImage()
        }
        
        resizedImageCache[cacheKey] = image
    }
    
    /**
     * 古いリサイズキャッシュを削除
     */
    private func removeOldestResizedCachedImage() {
        // 簡単な実装：現在ページから最も遠いものを削除
        guard let firstKey = resizedImageCache.keys.first else { return }
        
        var oldestKey = firstKey
        var maxDistance = 0
        
        for key in resizedImageCache.keys {
            if let indexString = key.components(separatedBy: "_").first,
               let index = Int(indexString) {
                let distance = abs(index - currentIndex)
                if distance > maxDistance {
                    maxDistance = distance
                    oldestKey = key
                }
            }
        }
        
        resizedImageCache.removeValue(forKey: oldestKey)
    }
    
    deinit {
        cancelAllBackgroundTasks()
        removeMemoryPressureObserver()
    }
}

enum PreloadPreference {
    case single
    case spread
}
// MARK: - Image decode helper
extension ImageManager {
    /// ImageIOを用いてNSImageへデコード（キャッシュ方針は設定に追従）
    private func decodeImage(data: Data, at index: Int?) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data) // フォールバック
        }

        let plan = buildDownsamplePlan(for: src)

        if let plan, let index, shouldUseIncrementalJPEG(for: src, plan: plan) {
            if let preview = decodeIncrementalJPEG(data: data, plan: plan, index: index) {
                return preview
            }
        }

        if let downsampled = createDownsampledImage(from: src, plan: plan) {
            return NSImage(cgImage: downsampled, size: NSSize(width: downsampled.width, height: downsampled.height))
        }

        let options = CZImageIOOptionsBuilder.buildDecodeOptions(cachePolicy: decodeCachePolicy)
        if let cg = CGImageSourceCreateImageAtIndex(src, 0, options) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        return NSImage(data: data) // フォールバック
    }

    private func createDownsampledImage(from source: CGImageSource, plan: DownsamplePlan?) -> CGImage? {
        guard let plan else { return nil }
        let options = CZImageIOOptionsBuilder.buildDownsampleOptions(
            maxPixels: plan.maxPixel,
            cachePolicy: decodeCachePolicy,
            subsampleFactor: plan.subsampleFactor
        )
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private func decodeIncrementalJPEG(data: Data, plan: DownsamplePlan, index: Int) -> NSImage? {
        let previewMax = max(incrementalPreviewMinPixels, plan.maxPixel / 2)
        let previewSubsample: Int?
        if let originalMax = plan.originalPixelMax {
            previewSubsample = determineSubsampleFactor(originalMax: originalMax, targetMax: CGFloat(previewMax))
        } else {
            previewSubsample = nil
        }

        let chunkSize = min(max(incrementalPreviewChunkBytes, data.count / 8), data.count)
        let previewData = data.prefix(chunkSize)
        let incremental = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(incremental, previewData as CFData, chunkSize == data.count)

        let previewOptions = CZImageIOOptionsBuilder.buildDownsampleOptions(
            maxPixels: previewMax,
            cachePolicy: decodeCachePolicy,
            subsampleFactor: previewSubsample
        )

        guard let cgPreview = CGImageSourceCreateThumbnailAtIndex(incremental, 0, previewOptions) else {
            return nil
        }

        if chunkSize < data.count {
            scheduleHighResolutionUpdate(for: index, data: data)
        }

        return NSImage(cgImage: cgPreview, size: NSSize(width: cgPreview.width, height: cgPreview.height))
    }

    private func shouldUseIncrementalJPEG(for source: CGImageSource, plan: DownsamplePlan) -> Bool {
        guard let type = CGImageSourceGetType(source) else { return false }
        let isJPEG: Bool
        if #available(macOS 11.0, *) {
            isJPEG = UTType(type as String)?.conforms(to: .jpeg) == true
        } else {
            isJPEG = UTTypeConformsTo(type, kUTTypeJPEG) || UTTypeConformsTo(type, kUTTypeJPEG2000)
        }
        guard isJPEG else { return false }
        guard let originalMax = plan.originalPixelMax else { return false }
        return originalMax > CGFloat(plan.maxPixel) * 1.5
    }

    private func scheduleHighResolutionUpdate(for index: Int, data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.pendingHighResTasks[index] == nil else { return }
            var workItemReference: DispatchWorkItem?
            let workItem = DispatchWorkItem(qos: .userInitiated) { [weak self] in
                guard let self else { return }
                guard workItemReference?.isCancelled != true else {
                    self.completeHighResTask(for: index)
                    return
                }
                let incremental = CGImageSourceCreateIncremental(nil)
                CGImageSourceUpdateData(incremental, data as CFData, true)
                let options = CZImageIOOptionsBuilder.buildDecodeOptions(cachePolicy: self.decodeCachePolicy)
                guard let cg = CGImageSourceCreateImageAtIndex(incremental, 0, options) else {
                    self.completeHighResTask(for: index)
                    return
                }
                let finalImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard workItemReference?.isCancelled != true else {
                        self.completeHighResTask(for: index)
                        return
                    }
                    self.cacheImage(finalImage, at: index)
                    if self.currentIndex == index {
                        NotificationCenter.default.post(name: .imageManagerDidUpdateImage, object: self, userInfo: ["index": index])
                    }
                    self.completeHighResTask(for: index)
                }
            }
            workItemReference = workItem
            self.pendingHighResTasks[index] = workItem
            self.preloadQueue.async(execute: workItem)
        }
    }

    private func completeHighResTask(for index: Int) {
        if Thread.isMainThread {
            pendingHighResTasks.removeValue(forKey: index)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.pendingHighResTasks.removeValue(forKey: index)
            }
        }
    }

    private func buildDownsamplePlan(for source: CGImageSource) -> DownsamplePlan? {
        let targetMax = desiredDisplayMaxPixelLength()

        guard let propertyDict = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = propertyDict[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = propertyDict[kCGImagePropertyPixelHeight] as? CGFloat else {
            // メタデータが取れない場合は最大ピクセル長のみ指定
            return DownsamplePlan(maxPixel: targetMax, subsampleFactor: nil, originalPixelMax: nil)
        }

        let originalMax = max(width, height)
        let skipThreshold = CGFloat(targetMax) * 1.05
        guard originalMax > skipThreshold else { return nil }

        let subsample = determineSubsampleFactor(originalMax: originalMax, targetMax: CGFloat(targetMax))
        return DownsamplePlan(maxPixel: targetMax, subsampleFactor: subsample, originalPixelMax: originalMax)
    }

    private func desiredDisplayMaxPixelLength() -> Int {
        if targetDisplaySize.width > 0, targetDisplaySize.height > 0 {
            let maxSide = max(targetDisplaySize.width, targetDisplaySize.height) * downsampleOverscanRatio
            return max(1, Int(ceil(maxSide)))
        }
        return fallbackMaxDisplayPixels
    }

    private func determineSubsampleFactor(originalMax: CGFloat, targetMax: CGFloat) -> Int? {
        guard originalMax > targetMax, targetMax > 0 else { return nil }
        let ratio = originalMax / targetMax
        if ratio >= 7.0 { return 8 }
        if ratio >= 3.5 { return 4 }
        if ratio >= 1.8 { return 2 }
        return nil
    }
}

private struct DownsamplePlan {
    let maxPixel: Int
    let subsampleFactor: Int?
    let originalPixelMax: CGFloat?
}

private struct PreloadPlan {
    let primaryOffsets: [Int]
    let additionalChunks: [[Int]]
}

extension Notification.Name {
    static let imageManagerDidUpdateImage = Notification.Name("com.dmng.CoverZip.imageManagerDidUpdateImage")
}

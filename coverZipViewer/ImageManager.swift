//
//  ImageManager.swift
//  coverZipViewer
//
//  Created by Nihondo on 2025/08/24.
//

import Foundation
import AppKit
import ImageIO
import QuartzCore
import os.signpost

/**
 * プレビュー用の画像管理クラス
 * ZIPファイル内の画像リストを管理し、ページング機能を提供する
 */
class ImageManager {

    enum DecodeQualityTier: String {
        case low
        case normal
    }

    private struct DecodeRequest {
        let widthBucket: Int
        let heightBucket: Int
        let maxPixelSize: Int
        let scaleToken: Int
    }

    private struct BucketSignature: Equatable {
        let singleWidthBucket: Int
        let singleHeightBucket: Int
        let spreadWidthBucket: Int
        let spreadHeightBucket: Int
        let scaleToken: Int
    }

    // 遅延ロード用のメタデータとZIPデータ
    private var imageEntryInfos: [CZImageEntryInfo] = []
    private var zipData: Data?
    private var currentIndex: Int = 0
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    // 見開きの左右組み合わせを1ページ分ずらすためのオフセット（0 or 1）
    private var spreadPairOffset: Int = 0

    // 画像キャッシュ（表示サイズバケット単位）
    private var resizedImageCache: [String: NSImage] = [:]
    private var resizedImageIndexMap: [String: Int] = [:]
    private let maxResizedCacheSize: Int = 32
    private let imageBucketStep: CGFloat = 64.0
    private let fallbackDecodeMaxPixelSize: Int = 2048
    private let lowQualityMaxPixelSingle: Int = 768
    private let lowQualityMaxPixelSpread: Int = 640
    private let singlePreloadBackwardPageCount = 1
    private let singlePreloadForwardPageCount = 5
    private let spreadPreloadBackwardSetCount = 1
    private let spreadPreloadForwardSetCount = 3

    private var targetDisplaySizeInPoints: NSSize = .zero
    private var targetDisplayScale: CGFloat = 1.0
    private var currentBucketSignature: BucketSignature?

    private let prerenderedLayerCache = PrerenderedLayerCache()
    private let decodeQueue = DispatchQueue(label: "com.dmng.coverzip.decode", qos: .userInitiated, attributes: .concurrent)
    private let layerBuildQueue = DispatchQueue(label: "com.dmng.coverzip.layerbuild", qos: .userInitiated)
    private let cacheStateQueue = DispatchQueue(label: "com.dmng.coverzip.cache.state", qos: .userInitiated)
    private let performanceLog = OSLog(subsystem: "com.dmng.CoverZip.coverZipViewer", category: "Performance")

    // デコードキャッシュ方針（設定から取得、デフォルトは .deferred）
    private var decodeCachePolicy: CZImageDecodeCachePolicy { AppSettings.shared.imageDecodeCachePolicy }
    // 全画像のバックグラウンド読み込み中かどうか（遅延ロード運用のため常にfalse）
    private(set) var isLoadingAll: Bool = false

    /// 現在ページのレイヤーが準備できたときの通知
    var onLayerPrerendered: ((Int) -> Void)?

    /// 現在表示中のページインデックス（0始まり）
    var currentPageIndex: Int { currentIndex }

    /// サムネイル生成用にZIPデータとエントリー情報を返す
    func getThumbnailSourceData() -> (zipData: Data, entries: [CZImageEntryInfo])? {
        guard let zipData = zipData else { return nil }
        return (zipData, imageEntryInfos)
    }

    /**
     * 表示対象サイズを設定（point）
     *
     * @param size 表示対象のサイズ（point）
     */
    @discardableResult
    func setTargetDisplaySize(_ size: NSSize) -> Bool {
        setTargetDisplaySize(size, backingScaleFactor: 1.0)
    }

    /**
     * 表示対象サイズを設定（point + scale）
     *
     * @param size 表示対象のサイズ（point）
     * @param backingScaleFactor バッキングスケール
     */
    @discardableResult
    func setTargetDisplaySize(_ size: NSSize, backingScaleFactor: CGFloat) -> Bool {
        guard size.width > 0 && size.height > 0 else { return false }

        let sanitizedScale = max(1.0, backingScaleFactor)
        let nextSignature = buildBucketSignature(sizeInPoints: size, scale: sanitizedScale)
        let wasSameSignature = currentBucketSignature == nextSignature
        let wasSamePointSize = targetDisplaySizeInPoints == size && abs(targetDisplayScale - sanitizedScale) < 0.001
        if wasSameSignature && wasSamePointSize {
            return false
        }

        targetDisplaySizeInPoints = size
        targetDisplayScale = sanitizedScale
        currentBucketSignature = nextSignature

        if !wasSameSignature {
            cacheStateQueue.sync {
                resizedImageCache.removeAll()
                resizedImageIndexMap.removeAll()
            }
            prerenderedLayerCache.clearAll()
            clearInFlightPrerenderState()
        }

        NSLog(
            "[ImageManager] Target display updated points=%dx%d scale=%.2f bucketsChanged=%d",
            Int(size.width),
            Int(size.height),
            sanitizedScale,
            wasSameSignature ? 0 : 1
        )
        return !wasSameSignature
    }

    /**
     * ZIPファイルから画像を読み込む（遅延ロード方式）
     *
     * @param url ZIPファイルのURL
     * @return 読み込み成功時はtrue、失敗時はfalse
     */
    func loadImages(from url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            os_signpost(.begin, log: performanceLog, name: "zipParse")
            let entryInfos = CZZip.imageEntryInfoList(from: data)
            os_signpost(.end, log: performanceLog, name: "zipParse")
            guard !entryInfos.isEmpty else { return false }

            zipData = data
            imageEntryInfos = entryInfos
            currentIndex = 0
            cacheStateQueue.sync {
                resizedImageCache.removeAll()
                resizedImageIndexMap.removeAll()
            }
            prerenderedLayerCache.clearAll()
            clearInFlightPrerenderState()
            setupMemoryPressureMonitoring()

            // 初期表示の体感を落とさないため先頭のみ先にデコード
            _ = getImageAtIndex(0)
            preloadAdjacentImages()

            NSLog("[ImageManager] Loaded %d images (lazy mode)", entryInfos.count)
            return true
        } catch {
            NSLog("[ImageManager] Failed to load ZIP: %@", String(describing: error))
            return false
        }
    }

    /**
     * 現在の画像を取得する
     */
    func getCurrentImage() -> NSImage? {
        getImageAtIndex(currentIndex, isSpreadMode: false, quality: .normal)
    }

    /// 指定ページ画像をバックグラウンドで取得する（完了はMainActor）
    func requestImageAsync(
        at index: Int,
        isSpreadMode: Bool,
        quality: DecodeQualityTier = .normal,
        completion: @escaping (_ pageIndex: Int, _ image: NSImage?) -> Void
    ) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let image = self.getImageAtIndex(index, isSpreadMode: isSpreadMode, quality: quality)
            DispatchQueue.main.async {
                completion(index, image)
            }
        }
    }

    /// 指定基準インデックスの見開き画像をバックグラウンドで取得する（完了はMainActor）
    func requestSpreadImagesAsync(
        baseIndex: Int,
        isRightToLeft: Bool,
        quality: DecodeQualityTier = .normal,
        completion: @escaping (_ baseIndex: Int, _ images: (left: NSImage?, right: NSImage?)) -> Void
    ) {
        decodeQueue.async { [weak self] in
            guard let self else { return }
            let images: (left: NSImage?, right: NSImage?)
            if let pair = self.resolveSpreadPairIndices(baseIndex: baseIndex, isRightToLeft: isRightToLeft) {
                let leftImage = pair.left.flatMap { self.getImageAtIndex($0, isSpreadMode: true, quality: quality) }
                let rightImage = pair.right.flatMap { self.getImageAtIndex($0, isSpreadMode: true, quality: quality) }
                images = (leftImage, rightImage)
            } else {
                images = (nil, nil)
            }
            DispatchQueue.main.async {
                completion(baseIndex, images)
            }
        }
    }

    /// 現在ページのキャッシュ済み画像のみを返す（未キャッシュならnil）
    func getCurrentImageIfCachedOnly(quality: DecodeQualityTier = .normal) -> NSImage? {
        getCachedImageAtIndex(currentIndex, isSpreadMode: false, quality: quality)
    }

    /**
     * 見開き用の画像を取得する（左右2ページ）
     */
    func getSpreadImages(isRightToLeft: Bool) -> (left: NSImage?, right: NSImage?) {
        guard let pair = resolveSpreadPairIndices(baseIndex: currentIndex, isRightToLeft: isRightToLeft) else {
            return (getCurrentImage(), nil)
        }

        let leftImage = pair.left.flatMap { getImageAtIndex($0, isSpreadMode: true, quality: .normal) }
        let rightImage = pair.right.flatMap { getImageAtIndex($0, isSpreadMode: true, quality: .normal) }
        return (leftImage, rightImage)
    }

    /// 現在ページに対応する見開きペアの実インデックスを返す
    func getCurrentSpreadPairIndices(isRightToLeft: Bool) -> (left: Int?, right: Int?) {
        guard let pair = resolveSpreadPairIndices(baseIndex: currentIndex, isRightToLeft: isRightToLeft) else {
            return (currentIndex, nil)
        }
        return pair
    }

    /// 見開きのキャッシュ済み画像のみを返す（未キャッシュならnil）
    func getSpreadImagesIfCachedOnly(
        isRightToLeft: Bool,
        quality: DecodeQualityTier = .normal
    ) -> (left: NSImage?, right: NSImage?) {
        guard let pair = resolveSpreadPairIndices(baseIndex: currentIndex, isRightToLeft: isRightToLeft) else {
            return (getCurrentImageIfCachedOnly(quality: quality), nil)
        }

        let leftImage = pair.left.flatMap { getCachedImageAtIndex($0, isSpreadMode: true, quality: quality) }
        let rightImage = pair.right.flatMap { getCachedImageAtIndex($0, isSpreadMode: true, quality: quality) }
        return (leftImage, rightImage)
    }

    func setSpreadPairOffset(_ value: Int) {
        spreadPairOffset = (value % 2 + 2) % 2
    }

    func getSpreadPairOffset() -> Int { spreadPairOffset }

    // MARK: - GPU 事前描画アクセス

    func getCurrentPrerenderedLayer() -> CALayer? {
        let request = buildDecodeRequest(isSpreadMode: false)
        let key = PrerenderedLayerCache.SingleKey(
            pageIndex: currentIndex,
            widthBucket: request.widthBucket,
            heightBucket: request.heightBucket,
            scaleToken: request.scaleToken
        )
        return prerenderedLayerCache.layer(for: key)
    }

    func getSpreadPrerenderedLayers(isRightToLeft: Bool) -> (left: CALayer?, right: CALayer?)? {
        guard let pair = resolveSpreadPairIndices(baseIndex: currentIndex, isRightToLeft: isRightToLeft) else {
            return nil
        }

        let request = buildDecodeRequest(isSpreadMode: true)
        let key = PrerenderedLayerCache.SpreadKey(
            leftIndex: pair.left,
            rightIndex: pair.right,
            widthBucket: request.widthBucket,
            heightBucket: request.heightBucket,
            scaleToken: request.scaleToken,
            isRightToLeft: isRightToLeft,
            spreadOffset: spreadPairOffset
        )
        return prerenderedLayerCache.spreadLayers(for: key)
    }

    func prerenderCurrentLayerIfNeeded(completion: ((CALayer?) -> Void)? = nil) {
        let request = buildDecodeRequest(isSpreadMode: false)
        let key = PrerenderedLayerCache.SingleKey(
            pageIndex: currentIndex,
            widthBucket: request.widthBucket,
            heightBucket: request.heightBucket,
            scaleToken: request.scaleToken
        )

        if let cached = prerenderedLayerCache.layer(for: key) {
            completion?(cached)
            return
        }
        guard beginSinglePrerender(key) else {
            return
        }

        let targetIndex = currentIndex
        decodeQueue.async { [weak self] in
            guard let self else { return }
            defer { self.endSinglePrerender(key) }
            guard let image = self.getImageAtIndex(targetIndex, isSpreadMode: false),
                  let layer = self.createPrerenderedLayer(from: image) else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            self.prerenderedLayerCache.store(layer, for: key)
            DispatchQueue.main.async {
                completion?(layer)
                self.onLayerPrerendered?(targetIndex)
            }
        }
    }

    func prerenderSpreadLayersIfNeeded(
        isRightToLeft: Bool,
        completion: (((left: CALayer?, right: CALayer?)) -> Void)? = nil
    ) {
        guard let pair = resolveSpreadPairIndices(baseIndex: currentIndex, isRightToLeft: isRightToLeft) else {
            completion?((nil, nil))
            return
        }

        let request = buildDecodeRequest(isSpreadMode: true)
        let spreadKey = PrerenderedLayerCache.SpreadKey(
            leftIndex: pair.left,
            rightIndex: pair.right,
            widthBucket: request.widthBucket,
            heightBucket: request.heightBucket,
            scaleToken: request.scaleToken,
            isRightToLeft: isRightToLeft,
            spreadOffset: spreadPairOffset
        )

        if let cached = prerenderedLayerCache.spreadLayers(for: spreadKey) {
            completion?(cached)
            return
        }
        guard beginSpreadPrerender(spreadKey) else {
            return
        }
        let targetIndex = currentIndex

        decodeQueue.async { [weak self] in
            guard let self else { return }
            defer { self.endSpreadPrerender(spreadKey) }

            let leftImage = pair.left.flatMap { self.getImageAtIndex($0, isSpreadMode: true) }
            let rightImage = pair.right.flatMap { self.getImageAtIndex($0, isSpreadMode: true) }
            let leftLayer = leftImage.flatMap { self.createPrerenderedLayer(from: $0) }
            let rightLayer = rightImage.flatMap { self.createPrerenderedLayer(from: $0) }

            self.prerenderedLayerCache.storeSpread(left: leftLayer, right: rightLayer, for: spreadKey)
            DispatchQueue.main.async {
                completion?((leftLayer, rightLayer))
                self.onLayerPrerendered?(targetIndex)
            }
        }
    }

    // MARK: - キャッシュ管理

    func preloadAdjacentImages(isSpreadMode: Bool = false, isRightToLeft: Bool = true) {
        let indicesToLoad: [Int]
        let spreadBaseIndices: [Int]
        if isSpreadMode {
            let spreadContext = buildSpreadPreloadContext(isRightToLeft: isRightToLeft)
            indicesToLoad = spreadContext.indices
            spreadBaseIndices = spreadContext.baseIndices
        } else {
            indicesToLoad = buildSinglePreloadIndices()
            spreadBaseIndices = []
        }

        let valid = Array(Set(indicesToLoad)).filter { $0 >= 0 && $0 < imageEntryInfos.count }
        if valid.isEmpty && spreadBaseIndices.isEmpty { return }

        decodeQueue.async { [weak self] in
            guard let self else { return }
            for index in valid {
                _ = self.getImageAtIndex(index, isSpreadMode: isSpreadMode)
                self.prerenderSingleLayerIfNeeded(pageIndex: index)
            }

            guard isSpreadMode else { return }
            for baseIndex in spreadBaseIndices {
                self.prerenderSpreadLayerIfNeeded(baseIndex: baseIndex, isRightToLeft: isRightToLeft)
            }
        }
    }

    func clearCache() {
        cacheStateQueue.sync {
            resizedImageCache.removeAll()
            resizedImageIndexMap.removeAll()
        }
        prerenderedLayerCache.clearAll()
        clearInFlightPrerenderState()
        NSLog("[ImageManager] All image cache cleared")
    }

    // MARK: - 非公開

    private func getImageAtIndex(
        _ index: Int,
        isSpreadMode: Bool = false,
        quality: DecodeQualityTier = .normal
    ) -> NSImage? {
        guard index >= 0, index < imageEntryInfos.count else { return nil }

        let request = buildDecodeRequest(isSpreadMode: isSpreadMode, quality: quality)
        let cacheKey = buildResizedCacheKey(index: index, request: request, isSpreadMode: isSpreadMode, quality: quality)
        if let cached = cacheStateQueue.sync(execute: { resizedImageCache[cacheKey] }) {
            return cached
        }

        guard let zipData else {
            NSLog("[ImageManager] ZIP data not available for lazy loading")
            return nil
        }

        os_signpost(.begin, log: performanceLog, name: "extractAndDecode", "index=%d maxPixelSize=%d", index, request.maxPixelSize)
        defer { os_signpost(.end, log: performanceLog, name: "extractAndDecode", "index=%d maxPixelSize=%d", index, request.maxPixelSize) }

        let entryInfo = imageEntryInfos[index]
        guard let imageData = CZZip.extractImageData(from: zipData, entryInfo: entryInfo) else {
            NSLog("[ImageManager] Failed to extract image at index %d: %@", index, entryInfo.filename)
            return nil
        }

        guard let image = decodeImage(data: imageData, maxPixelSize: request.maxPixelSize) else {
            NSLog("[ImageManager] Failed to decode image at index %d: %@", index, entryInfo.filename)
            return nil
        }

        cacheResizedImage(image, key: cacheKey, index: index)
        return image
    }

    private func getCachedImageAtIndex(
        _ index: Int,
        isSpreadMode: Bool = false,
        quality: DecodeQualityTier = .normal
    ) -> NSImage? {
        guard index >= 0, index < imageEntryInfos.count else { return nil }
        let request = buildDecodeRequest(isSpreadMode: isSpreadMode, quality: quality)
        let cacheKey = buildResizedCacheKey(index: index, request: request, isSpreadMode: isSpreadMode, quality: quality)
        return cacheStateQueue.sync(execute: { resizedImageCache[cacheKey] })
    }

    private func buildDecodeRequest(
        isSpreadMode: Bool,
        quality: DecodeQualityTier = .normal
    ) -> DecodeRequest {
        buildDecodeRequest(
            sizeInPoints: targetDisplaySizeInPoints,
            scale: targetDisplayScale,
            isSpreadMode: isSpreadMode,
            quality: quality
        )
    }

    private func buildDecodeRequest(
        sizeInPoints: NSSize,
        scale: CGFloat,
        isSpreadMode: Bool,
        quality: DecodeQualityTier
    ) -> DecodeRequest {
        let fallbackScaleToken = max(100, Int((max(1.0, scale) * 100.0).rounded()))

        guard sizeInPoints.width > 0 && sizeInPoints.height > 0 else {
            return DecodeRequest(
                widthBucket: fallbackDecodeMaxPixelSize,
                heightBucket: fallbackDecodeMaxPixelSize,
                maxPixelSize: fallbackDecodeMaxPixelSize,
                scaleToken: fallbackScaleToken
            )
        }

        let baseWidth = isSpreadMode ? max(1.0, sizeInPoints.width / 2.0) : max(1.0, sizeInPoints.width)
        let baseHeight = max(1.0, sizeInPoints.height)
        let sanitizedScale = max(1.0, scale)

        let pixelWidth = baseWidth * sanitizedScale
        let pixelHeight = baseHeight * sanitizedScale
        var widthBucket = bucket(pixelWidth)
        var heightBucket = bucket(pixelHeight)
        var maxPixel = max(widthBucket, heightBucket)

        if quality == .low {
            let lowQualityCap = isSpreadMode ? lowQualityMaxPixelSpread : lowQualityMaxPixelSingle
            let capped = max(Int(imageBucketStep), min(lowQualityCap, maxPixel))
            maxPixel = capped
            widthBucket = min(widthBucket, capped)
            heightBucket = min(heightBucket, capped)
        }

        return DecodeRequest(
            widthBucket: widthBucket,
            heightBucket: heightBucket,
            maxPixelSize: maxPixel,
            scaleToken: fallbackScaleToken
        )
    }

    private func buildBucketSignature(sizeInPoints: NSSize, scale: CGFloat) -> BucketSignature {
        let single = buildDecodeRequest(sizeInPoints: sizeInPoints, scale: scale, isSpreadMode: false, quality: .normal)
        let spread = buildDecodeRequest(sizeInPoints: sizeInPoints, scale: scale, isSpreadMode: true, quality: .normal)
        return BucketSignature(
            singleWidthBucket: single.widthBucket,
            singleHeightBucket: single.heightBucket,
            spreadWidthBucket: spread.widthBucket,
            spreadHeightBucket: spread.heightBucket,
            scaleToken: single.scaleToken
        )
    }

    private func bucket(_ value: CGFloat) -> Int {
        let rounded = ceil(value / imageBucketStep) * imageBucketStep
        return max(Int(imageBucketStep), Int(rounded))
    }

    private func buildResizedCacheKey(
        index: Int,
        request: DecodeRequest,
        isSpreadMode: Bool,
        quality: DecodeQualityTier
    ) -> String {
        let modeToken = isSpreadMode ? "spread" : "single"
        let qualityToken = (quality == .low) ? "low" : "normal"
        return "\(index)_\(modeToken)_\(qualityToken)_\(request.widthBucket)x\(request.heightBucket)_s\(request.scaleToken)"
    }

    private func cacheResizedImage(_ image: NSImage, key: String, index: Int) {
        cacheStateQueue.sync {
            if resizedImageCache.count >= maxResizedCacheSize && resizedImageCache[key] == nil {
                removeOldestResizedCachedImageLocked()
            }
            resizedImageCache[key] = image
            resizedImageIndexMap[key] = index
        }
    }

    private func removeOldestResizedCachedImageLocked() {
        guard let firstKey = resizedImageCache.keys.first else { return }
        var victimKey = firstKey
        var maxDistance = -1

        for key in resizedImageCache.keys {
            let pageIndex = resizedImageIndexMap[key] ?? 0
            let distance = abs(pageIndex - currentIndex)
            if distance > maxDistance {
                maxDistance = distance
                victimKey = key
            }
        }

        resizedImageCache.removeValue(forKey: victimKey)
        resizedImageIndexMap.removeValue(forKey: victimKey)
    }

    private func buildSinglePreloadIndices() -> [Int] {
        var indices: [Int] = []
        if singlePreloadBackwardPageCount > 0 {
            for offset in 1...singlePreloadBackwardPageCount {
                indices.append(currentIndex - offset)
            }
        }
        if singlePreloadForwardPageCount > 0 {
            for offset in 1...singlePreloadForwardPageCount {
                indices.append(currentIndex + offset)
            }
        }
        return indices
    }

    private func buildSpreadPreloadContext(isRightToLeft: Bool) -> (indices: [Int], baseIndices: [Int]) {
        var indices: [Int] = []
        var baseIndices: [Int] = []

        let anchorBaseIndex = currentIndex == 0 ? 1 : currentIndex

        if currentIndex == 0 {
            baseIndices.append(0)
        }

        baseIndices.append(anchorBaseIndex)
        if spreadPreloadForwardSetCount > 0 {
            for step in 1...spreadPreloadForwardSetCount {
                baseIndices.append(anchorBaseIndex + (step * 2))
            }
        }
        if spreadPreloadBackwardSetCount > 0 {
            for step in 1...spreadPreloadBackwardSetCount {
                baseIndices.append(anchorBaseIndex - (step * 2))
            }
        }

        for baseIndex in baseIndices {
            guard let currentPair = resolveSpreadPairIndices(baseIndex: baseIndex, isRightToLeft: isRightToLeft) else {
                continue
            }
            indices.append(contentsOf: [currentPair.left, currentPair.right].compactMap { $0 })
        }

        let validBaseIndices = Array(Set(baseIndices)).sorted()
        return (indices, validBaseIndices)
    }

    private func resolveSpreadPairIndices(baseIndex: Int, isRightToLeft: Bool) -> (left: Int?, right: Int?)? {
        guard !imageEntryInfos.isEmpty else { return nil }
        guard baseIndex >= 0, baseIndex < imageEntryInfos.count else { return nil }

        if baseIndex == 0 {
            return (0, nil)
        }

        let parity = (baseIndex + spreadPairOffset) % 2
        let leftIndex: Int
        let rightIndex: Int

        if isRightToLeft {
            if parity == 1 {
                leftIndex = baseIndex + 1
                rightIndex = baseIndex
            } else {
                leftIndex = baseIndex
                rightIndex = baseIndex - 1
            }
        } else {
            if parity == 1 {
                leftIndex = baseIndex
                rightIndex = baseIndex + 1
            } else {
                leftIndex = baseIndex - 1
                rightIndex = baseIndex
            }
        }

        let left = (leftIndex >= 0 && leftIndex < imageEntryInfos.count) ? leftIndex : nil
        let right = (rightIndex >= 0 && rightIndex < imageEntryInfos.count) ? rightIndex : nil
        return (left, right)
    }

    private func prerenderSingleLayerIfNeeded(pageIndex: Int) {
        guard pageIndex >= 0, pageIndex < imageEntryInfos.count else { return }
        let request = buildDecodeRequest(isSpreadMode: false)
        let key = PrerenderedLayerCache.SingleKey(
            pageIndex: pageIndex,
            widthBucket: request.widthBucket,
            heightBucket: request.heightBucket,
            scaleToken: request.scaleToken
        )

        if prerenderedLayerCache.layer(for: key) != nil { return }
        guard beginSinglePrerender(key) else { return }

        layerBuildQueue.async { [weak self] in
            guard let self else { return }
            defer { self.endSinglePrerender(key) }
            guard let image = self.getImageAtIndex(pageIndex, isSpreadMode: false),
                  let layer = self.createPrerenderedLayer(from: image) else { return }
            self.prerenderedLayerCache.store(layer, for: key)
            DispatchQueue.main.async {
                self.onLayerPrerendered?(pageIndex)
            }
        }
    }

    private func prerenderSpreadLayerIfNeeded(baseIndex: Int, isRightToLeft: Bool) {
        guard let pair = resolveSpreadPairIndices(baseIndex: baseIndex, isRightToLeft: isRightToLeft) else { return }
        let request = buildDecodeRequest(isSpreadMode: true)
        let spreadKey = PrerenderedLayerCache.SpreadKey(
            leftIndex: pair.left,
            rightIndex: pair.right,
            widthBucket: request.widthBucket,
            heightBucket: request.heightBucket,
            scaleToken: request.scaleToken,
            isRightToLeft: isRightToLeft,
            spreadOffset: spreadPairOffset
        )
        if prerenderedLayerCache.spreadLayers(for: spreadKey) != nil { return }
        guard beginSpreadPrerender(spreadKey) else { return }

        layerBuildQueue.async { [weak self] in
            guard let self else { return }
            defer { self.endSpreadPrerender(spreadKey) }
            let leftImage = pair.left.flatMap { self.getImageAtIndex($0, isSpreadMode: true) }
            let rightImage = pair.right.flatMap { self.getImageAtIndex($0, isSpreadMode: true) }
            let leftLayer = leftImage.flatMap { self.createPrerenderedLayer(from: $0) }
            let rightLayer = rightImage.flatMap { self.createPrerenderedLayer(from: $0) }
            self.prerenderedLayerCache.storeSpread(left: leftLayer, right: rightLayer, for: spreadKey)
            DispatchQueue.main.async {
                self.onLayerPrerendered?(baseIndex)
            }
        }
    }

    private func createPrerenderedLayer(from image: NSImage) -> CALayer? {
        guard let cgImage = extractCGImage(from: image) else { return nil }
        return DispatchQueue.main.sync {
            let layer = CALayer()
            layer.contents = cgImage
            layer.contentsGravity = .resizeAspect
            layer.minificationFilter = .trilinear
            layer.magnificationFilter = .linear
            layer.contentsScale = max(1.0, targetDisplayScale)
            layer.setNeedsDisplay()
            layer.displayIfNeeded()
            return layer
        }
    }

    private func extractCGImage(from image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cgImage
        }

        if let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData) {
            return bitmapRep.cgImage
        }

        for rep in image.representations {
            if let bitmapRep = rep as? NSBitmapImageRep, let cgImage = bitmapRep.cgImage {
                return cgImage
            }
        }

        return nil
    }

    // MARK: - メモリ管理

    private func setupMemoryPressureMonitoring() {
        removeMemoryPressureObserver()

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            self?.handleMemoryPressure()
        }
        source.resume()
        memoryPressureSource = source
    }

    private func removeMemoryPressureObserver() {
        if let source = memoryPressureSource {
            source.cancel()
            memoryPressureSource = nil
        }
    }

    private func handleMemoryPressure() {
        let currentSingleRequest = buildDecodeRequest(isSpreadMode: false)
        let currentSingleKey = PrerenderedLayerCache.SingleKey(
            pageIndex: currentIndex,
            widthBucket: currentSingleRequest.widthBucket,
            heightBucket: currentSingleRequest.heightBucket,
            scaleToken: currentSingleRequest.scaleToken
        )

        let currentIndexSnapshot = currentIndex
        cacheStateQueue.sync {
            resizedImageCache = resizedImageCache.filter { key, _ in
                (resizedImageIndexMap[key] ?? -1) == currentIndexSnapshot
            }
            resizedImageIndexMap = resizedImageIndexMap.filter { resizedImageCache[$0.key] != nil }
        }
        prerenderedLayerCache.clearExcept(singleKey: currentSingleKey, spreadKey: nil)
        clearInFlightPrerenderState()
        NSLog("[ImageManager] Memory pressure handled at index=%d", currentIndexSnapshot)
    }

    private let prerenderStateQueue = DispatchQueue(label: "com.dmng.coverzip.prerender.state", qos: .userInitiated)
    private var inFlightSinglePrerenderKeys: Set<PrerenderedLayerCache.SingleKey> = []
    private var inFlightSpreadPrerenderKeys: Set<PrerenderedLayerCache.SpreadKey> = []

    private func beginSinglePrerender(_ key: PrerenderedLayerCache.SingleKey) -> Bool {
        prerenderStateQueue.sync {
            if inFlightSinglePrerenderKeys.contains(key) {
                return false
            }
            inFlightSinglePrerenderKeys.insert(key)
            return true
        }
    }

    private func endSinglePrerender(_ key: PrerenderedLayerCache.SingleKey) {
        prerenderStateQueue.sync {
            _ = inFlightSinglePrerenderKeys.remove(key)
        }
    }

    private func beginSpreadPrerender(_ key: PrerenderedLayerCache.SpreadKey) -> Bool {
        prerenderStateQueue.sync {
            if inFlightSpreadPrerenderKeys.contains(key) {
                return false
            }
            inFlightSpreadPrerenderKeys.insert(key)
            return true
        }
    }

    private func endSpreadPrerender(_ key: PrerenderedLayerCache.SpreadKey) {
        prerenderStateQueue.sync {
            _ = inFlightSpreadPrerenderKeys.remove(key)
        }
    }

    private func clearInFlightPrerenderState() {
        prerenderStateQueue.sync {
            inFlightSinglePrerenderKeys.removeAll()
            inFlightSpreadPrerenderKeys.removeAll()
        }
    }

    deinit {
        removeMemoryPressureObserver()
    }
}

// MARK: - ナビゲーション
extension ImageManager {
    /**
     * 現在の画像のファイル名を取得する
     */
    func getCurrentImageName() -> String {
        guard !imageEntryInfos.isEmpty, currentIndex >= 0, currentIndex < imageEntryInfos.count else {
            return ""
        }
        return imageEntryInfos[currentIndex].filename
    }

    /**
     * 次の画像に移動する
     */
    func nextImage(isSpreadMode: Bool = false) -> Bool {
        guard !imageEntryInfos.isEmpty else { return false }

        if isSpreadMode {
            if currentIndex == 0 {
                guard currentIndex < imageEntryInfos.count - 1 else { return false }
                currentIndex = 1
            } else {
                let nextIndex = currentIndex + 2
                guard nextIndex < imageEntryInfos.count else { return false }
                currentIndex = nextIndex
            }
        } else {
            guard currentIndex < imageEntryInfos.count - 1 else { return false }
            currentIndex += 1
        }

        preloadAdjacentImages(isSpreadMode: false)
        return true
    }

    /**
     * 前の画像に移動する
     */
    func previousImage(isSpreadMode: Bool = false) -> Bool {
        guard !imageEntryInfos.isEmpty, currentIndex > 0 else { return false }

        if isSpreadMode {
            if currentIndex == 1 {
                currentIndex = 0
            } else {
                currentIndex = max(0, currentIndex - 2)
            }
        } else {
            currentIndex -= 1
        }

        preloadAdjacentImages(isSpreadMode: false)
        return true
    }

    /**
     * 画像の総数を取得する
     */
    func getImageCount() -> Int {
        imageEntryInfos.count
    }

    /**
     * 現在のページ番号を取得する（1始まり）
     */
    func getCurrentPageNumber() -> Int {
        currentIndex + 1
    }

    /// 指定ページへ移動（1始まり）
    func goToPage(_ page: Int) -> Bool {
        guard !imageEntryInfos.isEmpty else { return false }
        let clamped = max(1, min(page, imageEntryInfos.count))
        currentIndex = clamped - 1
        preloadAdjacentImages()
        return true
    }

    /**
     * 画像があるかどうかを確認する
     */
    func hasImages() -> Bool {
        !imageEntryInfos.isEmpty
    }

    /**
     * 現在のページが表紙かどうかを判定する
     */
    func isCoverPage() -> Bool {
        currentIndex == 0
    }
}

// MARK: - 画像デコード補助
extension ImageManager {
    /// ImageIOを用いてNSImageへデコード（キャッシュ方針は設定に追従）
    private func decodeImage(data: Data, maxPixelSize: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }

        let thumbnailOptions = CZImageIOOptionsBuilder.buildThumbnailOptions(
            maxPixels: max(1, maxPixelSize),
            cachePolicy: decodeCachePolicy
        )
        let startTime = CFAbsoluteTimeGetCurrent()
        if let thumbnailImage = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbnailOptions) {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            logDecodeResult(source: src, decodedImage: thumbnailImage, elapsedMs: elapsedMs, maxPixelSize: maxPixelSize)
            return NSImage(cgImage: thumbnailImage, size: NSSize(width: thumbnailImage.width, height: thumbnailImage.height))
        }

        // サムネイル生成失敗時のみ従来デコードへフォールバック
        let options = CZImageIOOptionsBuilder.buildDecodeOptions(cachePolicy: decodeCachePolicy)
        if let cg = CGImageSourceCreateImageAtIndex(src, 0, options) {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            logDecodeResult(source: src, decodedImage: cg, elapsedMs: elapsedMs, maxPixelSize: nil)
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }

        return NSImage(data: data)
    }

    private func logDecodeResult(source: CGImageSource, decodedImage: CGImage, elapsedMs: CFTimeInterval, maxPixelSize: Int?) {
        let decodedWidth = decodedImage.width
        let decodedHeight = decodedImage.height
        var sourceWidth = 0
        var sourceHeight = 0

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        }

        var shrinkRatioText = "n/a"
        if sourceWidth > 0 && sourceHeight > 0 {
            let sourceMax = Double(max(sourceWidth, sourceHeight))
            let decodedMax = Double(max(decodedWidth, decodedHeight))
            if sourceMax > 0 {
                shrinkRatioText = String(format: "%.3f", decodedMax / sourceMax)
            }
        }

        if let maxPixelSize {
            NSLog(
                "[ImageManager][Decode] mode=downsample max=%d src=%dx%d decoded=%dx%d ratio=%@ time=%.2fms",
                maxPixelSize,
                sourceWidth,
                sourceHeight,
                decodedWidth,
                decodedHeight,
                shrinkRatioText,
                elapsedMs
            )
        } else {
            NSLog(
                "[ImageManager][Decode] mode=fallback-full src=%dx%d decoded=%dx%d ratio=%@ time=%.2fms",
                sourceWidth,
                sourceHeight,
                decodedWidth,
                decodedHeight,
                shrinkRatioText,
                elapsedMs
            )
        }
    }
}

// MARK: - 事前描画レイヤーキャッシュ
private final class PrerenderedLayerCache {
    struct SingleKey: Hashable {
        let pageIndex: Int
        let widthBucket: Int
        let heightBucket: Int
        let scaleToken: Int
    }

    struct SpreadKey: Hashable {
        let leftIndex: Int?
        let rightIndex: Int?
        let widthBucket: Int
        let heightBucket: Int
        let scaleToken: Int
        let isRightToLeft: Bool
        let spreadOffset: Int
    }

    private let queue = DispatchQueue(label: "com.dmng.coverzip.prerender.cache", qos: .userInitiated)
    private var singleCache: [SingleKey: CALayer] = [:]
    private var spreadCache: [SpreadKey: (left: CALayer?, right: CALayer?)] = [:]
    private var singleAccessTick: [SingleKey: Int] = [:]
    private var spreadAccessTick: [SpreadKey: Int] = [:]
    private var tickCounter: Int = 0

    private let maxSingleCacheSize = 10
    private let maxSpreadCacheSize = 6

    func layer(for key: SingleKey) -> CALayer? {
        queue.sync {
            guard let layer = singleCache[key] else { return nil }
            tickCounter += 1
            singleAccessTick[key] = tickCounter
            return layer
        }
    }

    func spreadLayers(for key: SpreadKey) -> (left: CALayer?, right: CALayer?)? {
        queue.sync {
            guard let layers = spreadCache[key] else { return nil }
            tickCounter += 1
            spreadAccessTick[key] = tickCounter
            return layers
        }
    }

    func store(_ layer: CALayer, for key: SingleKey) {
        queue.sync {
            if singleCache[key] == nil && singleCache.count >= maxSingleCacheSize {
                evictOldestSingle()
            }
            singleCache[key] = layer
            tickCounter += 1
            singleAccessTick[key] = tickCounter
        }
    }

    func storeSpread(left: CALayer?, right: CALayer?, for key: SpreadKey) {
        queue.sync {
            if spreadCache[key] == nil && spreadCache.count >= maxSpreadCacheSize {
                evictOldestSpread()
            }
            spreadCache[key] = (left, right)
            tickCounter += 1
            spreadAccessTick[key] = tickCounter
        }
    }

    func clearExcept(singleKey: SingleKey?, spreadKey: SpreadKey?) {
        queue.sync {
            if let singleKey, let layer = singleCache[singleKey] {
                singleCache = [singleKey: layer]
                singleAccessTick = [singleKey: singleAccessTick[singleKey] ?? 0]
            } else {
                singleCache.removeAll()
                singleAccessTick.removeAll()
            }

            if let spreadKey, let layers = spreadCache[spreadKey] {
                spreadCache = [spreadKey: layers]
                spreadAccessTick = [spreadKey: spreadAccessTick[spreadKey] ?? 0]
            } else {
                spreadCache.removeAll()
                spreadAccessTick.removeAll()
            }
        }
    }

    func clearAll() {
        queue.sync {
            singleCache.removeAll()
            spreadCache.removeAll()
            singleAccessTick.removeAll()
            spreadAccessTick.removeAll()
        }
    }

    private func evictOldestSingle() {
        guard let victim = singleAccessTick.min(by: { $0.value < $1.value })?.key else { return }
        singleCache.removeValue(forKey: victim)
        singleAccessTick.removeValue(forKey: victim)
    }

    private func evictOldestSpread() {
        guard let victim = spreadAccessTick.min(by: { $0.value < $1.value })?.key else { return }
        spreadCache.removeValue(forKey: victim)
        spreadAccessTick.removeValue(forKey: victim)
    }
}

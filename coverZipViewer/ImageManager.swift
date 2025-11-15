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

    /**
     * プリロード設定を変更する
     *
     * 表示モード（単ページ/見開き）に応じて最適なプリロード範囲を設定
     * 見開きモードでは広範囲（±4ページ）、単ページでは狭範囲（±3ページ）をプリロード
     *
     * @param preference プリロード設定（.single または .spread）
     */
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

    /**
     * 見開きペアリングオフセットをトグル（0<->1）
     *
     * 見開き表示で左右のページ組み合わせを1ページずらすための設定
     * 例：オフセット0では2-3ページが見開き、オフセット1では1-2ページが見開き
     */
    func toggleSpreadPairOffset() {
        spreadPairOffset = 1 - spreadPairOffset
    }

    /**
     * 見開きペアリングオフセットを設定する
     *
     * @param value オフセット値（0または1）
     */
    func setSpreadPairOffset(_ value: Int) {
        spreadPairOffset = (value % 2 + 2) % 2
    }

    /**
     * 現在の見開きペアリングオフセットを取得する
     *
     * @return オフセット値（0または1）
     */
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

    /**
     * 元画像をキャッシュに追加する
     *
     * キャッシュが上限に達している場合は、現在のページから最も離れた画像を削除
     * 最大キャッシュサイズは10枚に制限
     *
     * @param image キャッシュする画像
     * @param index 画像のインデックス
     */
    private func cacheImage(_ image: NSImage, at index: Int) {
        if imageCache.count >= maxCacheSize {
            removeOldestCachedImage()
        }
        imageCache[index] = image
    }

    /**
     * 現在のページから最も離れたキャッシュ画像を削除する
     *
     * LRU（Least Recently Used）方式ではなく、現在ページからの距離ベースで削除
     * これにより、ページ送りの方向に関わらず効率的なキャッシュが維持される
     */
    private func removeOldestCachedImage() {
        guard !imageCache.isEmpty else { return }

        // 現在のインデックスから最も離れているキャッシュを削除
        let farthestIndex = imageCache.keys.max { abs($0 - currentIndex) < abs($1 - currentIndex) }
        if let indexToRemove = farthestIndex {
            imageCache.removeValue(forKey: indexToRemove)
        }
    }
    
    /**
     * 現在のページの隣接画像をプリロードする
     *
     * プリロードは2段階で実行される：
     * 1. Primary段階: 最も近い隣接ページ（見開き時±2、単ページ時±1）
     * 2. Additional段階: より遠いページ（見開き時±4、単ページ時±3）
     *
     * Primary完了後に自動的にAdditional段階が開始される
     */
    func preloadAdjacentImages() {
        guard hasImages() else { return }
        let plan = buildPreloadPlan()
        NSLog("[ImageManager] Preload plan primary=%@ additional=%@", plan.primaryOffsets.description, plan.additionalChunks.description)
        pendingPreloadChunks = plan.additionalChunks
        schedulePreloadTasks(for: plan.primaryOffsets, cancelOthers: true)
    }

    /**
     * 指定されたインデックスのプリロードタスクをスケジュールする
     *
     * @param indices プリロード対象のインデックス配列
     * @param cancelOthers trueの場合、対象外の既存タスクをキャンセル
     */
    private func schedulePreloadTasks(for indices: [Int], cancelOthers: Bool) {
        // 有効なインデックスのみをフィルタリング（範囲内かつ未キャッシュ）
        let validIndices = indices.filter {
            $0 >= 0 && $0 < imageEntryInfos.count && imageCache[$0] == nil
        }
        NSLog("[ImageManager] Scheduling preload targets=%@ (cancelOthers=%@)", validIndices.description, String(cancelOthers))

        // 不要になったタスクをキャンセル（ページ移動時など）
        if cancelOthers {
            let keepSet = Set(validIndices)
            cancelObsoletePreloadTasks(keeping: keepSet)
        }

        // 各インデックスのプリロードタスクを作成・実行
        for index in validIndices where pendingPreloadTasks[index] == nil {
            let workItem = makePreloadWorkItem(for: index)
            pendingPreloadTasks[index] = workItem
            preloadQueue.async(execute: workItem)
        }
    }

    /**
     * 不要になったプリロードタスクをキャンセルする
     *
     * ページ移動時など、現在位置から離れたページのプリロードタスクを中止する
     * これにより、無駄なメモリ使用と処理を防ぐ
     *
     * @param keepSet 保持するインデックスのセット（これ以外はキャンセル）
     */
    private func cancelObsoletePreloadTasks(keeping keepSet: Set<Int>) {
        guard !pendingPreloadTasks.isEmpty else { return }
        var removalTargets: [Int] = []
        for (index, workItem) in pendingPreloadTasks where !keepSet.contains(index) {
            workItem.cancel()
            removalTargets.append(index)
        }
        removalTargets.forEach { pendingPreloadTasks.removeValue(forKey: $0) }
    }

    /**
     * プリロード用のワークアイテムを作成する
     *
     * キャンセル可能なワークアイテムを作成し、バックグラウンドで画像をロード
     * キャンセルチェックを定期的に行い、不要になった処理を中断できる
     *
     * @param index プリロード対象のインデックス
     * @return キャンセル可能なDispatchWorkItem
     */
    private func makePreloadWorkItem(for index: Int) -> DispatchWorkItem {
        var workItemReference: DispatchWorkItem?
        let workItem = DispatchWorkItem(qos: .userInitiated) { [weak self] in
            guard let self else { return }
            // キャンセルチェック用のクロージャ
            let isCancelled: () -> Bool = { workItemReference?.isCancelled ?? true }
            self.loadImageAtIndex(index, isCancelled: isCancelled)
            self.completePreloadTask(for: index, workItem: workItemReference)
        }
        workItemReference = workItem
        return workItem
    }

    /**
     * プリロードタスクの完了処理を行う
     *
     * タスクを追跡辞書から削除し、次のプリロードチャンクをスケジュールする
     * 全てのPrimaryタスクが完了すると、自動的にAdditionalチャンクが開始される
     *
     * @param index 完了したタスクのインデックス
     * @param workItem 完了したワークアイテム
     */
    private func completePreloadTask(for index: Int, workItem: DispatchWorkItem?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let current = self.pendingPreloadTasks[index], let workItem, current === workItem {
                self.pendingPreloadTasks.removeValue(forKey: index)
            }
            // 全タスク完了時に次のチャンクをスケジュール
            self.scheduleNextPreloadChunkIfNeeded()
        }
    }

    /**
     * 次のプリロードチャンクをスケジュールする（必要な場合のみ）
     *
     * 全てのプリロードタスクが完了し、追加チャンクが残っている場合に実行
     * Primary段階（±2）完了後、Additional段階（±4）を自動的に開始
     */
    private func scheduleNextPreloadChunkIfNeeded() {
        guard pendingPreloadTasks.isEmpty, !pendingPreloadChunks.isEmpty else { return }
        let nextOffsets = pendingPreloadChunks.removeFirst()
        NSLog("[ImageManager] Scheduling next preload chunk=%@", nextOffsets.description)
        schedulePreloadTasks(for: nextOffsets, cancelOthers: false)
    }

    /**
     * プリロード計画を構築する
     *
     * 表示モードに応じて最適なプリロード範囲を決定
     *
     * 【単ページモード】
     * - Primary: ±1（前後1ページ、計2ページ）
     * - Additional: ±2, ±3（段階的にプリロード、計4ページ）
     *
     * 【見開きモード】
     * - Primary: ±1〜±2（前後2ページずつ、計4ページ）
     * - Additional: ±3〜±4（さらに遠いページ、計4ページ）
     *
     * @return プリロード計画（Primary段階とAdditional段階のインデックス）
     */
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

    /**
     * 指定されたインデックスの画像をバックグラウンドでロードする
     *
     * キャンセルチェックを各段階で実行し、不要になった処理を即座に中断
     * これにより、ページ移動時のレスポンスが向上する
     *
     * @param index ロード対象のインデックス
     * @param isCancelled キャンセル状態をチェックするクロージャ
     */
    private func loadImageAtIndex(_ index: Int, isCancelled: (() -> Bool)?) {
        guard index >= 0, index < imageEntryInfos.count else { return }
        guard isCancelled?() != true else { return }
        if imageCache[index] != nil { return }

        guard let zipData = zipData else { return }
        guard isCancelled?() != true else { return }

        // ZIPから画像データを抽出
        let entryInfo = imageEntryInfos[index]
        guard let imageData = CZZip.extractImageData(from: zipData, entryInfo: entryInfo) else {
            return
        }
        guard isCancelled?() != true else { return }

        // 画像をデコード
        if let image = decodeImage(data: imageData, at: index) {
            guard isCancelled?() != true else { return }
            // メインスレッドでキャッシュに追加
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
    
    /**
     * 全ての画像キャッシュをクリアする
     *
     * 現在表示中の画像のみを保持し、それ以外を削除
     * デコードキャッシュポリシー変更時などに使用
     */
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

    /**
     * 全てのバックグラウンドタスクをキャンセルする
     *
     * プリロードタスクと高解像度差し替えタスクを全て中止
     * ファイル切り替え時やキャッシュクリア時に使用
     */
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
    /**
     * ImageIOを用いて画像データをNSImageへデコードする
     *
     * デコード戦略：
     * 1. ダウンサンプリング計画を構築（表示サイズに最適化）
     * 2. 大きなJPEGの場合、段階的デコード（低解像→高解像）
     * 3. 通常のダウンサンプリングデコード
     * 4. フォールバック（通常デコード）
     *
     * @param data 画像データ
     * @param index 画像のインデックス（段階的デコード用）
     * @return デコードされたNSImage、失敗時はnil
     */
    private func decodeImage(data: Data, at index: Int?) -> NSImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data) // フォールバック
        }

        let plan = buildDownsamplePlan(for: src)

        // 大きなJPEG画像の場合、段階的デコードを使用
        if let plan, let index, shouldUseIncrementalJPEG(for: src, plan: plan) {
            if let preview = decodeIncrementalJPEG(data: data, plan: plan, index: index) {
                return preview
            }
        }

        // ダウンサンプリングデコード
        if let downsampled = createDownsampledImage(from: src, plan: plan) {
            return NSImage(cgImage: downsampled, size: NSSize(width: downsampled.width, height: downsampled.height))
        }

        // フォールバック：通常デコード
        let options = CZImageIOOptionsBuilder.buildDecodeOptions(cachePolicy: decodeCachePolicy)
        if let cg = CGImageSourceCreateImageAtIndex(src, 0, options) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        return NSImage(data: data) // 最終フォールバック
    }

    /**
     * ダウンサンプリングされた画像を生成する
     *
     * 表示サイズに合わせて画像を縮小してデコードすることで、
     * メモリ使用量とデコード時間を大幅に削減
     *
     * @param source 画像ソース
     * @param plan ダウンサンプリング計画
     * @return ダウンサンプリングされたCGImage
     */
    private func createDownsampledImage(from source: CGImageSource, plan: DownsamplePlan?) -> CGImage? {
        guard let plan else { return nil }
        let options = CZImageIOOptionsBuilder.buildDownsampleOptions(
            maxPixels: plan.maxPixel,
            cachePolicy: decodeCachePolicy,
            subsampleFactor: plan.subsampleFactor
        )
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /**
     * 段階的JPEG デコードを実行する
     *
     * 大きなJPEG画像を2段階でデコード：
     * 1. 低解像度プレビュー（データの一部のみを使用）→ 即座に表示
     * 2. 高解像度画像（全データ）→ バックグラウンドでデコード後に差し替え
     *
     * これにより、大きな画像でも即座に表示できる
     *
     * @param data 画像データ
     * @param plan ダウンサンプリング計画
     * @param index 画像のインデックス（高解像度差し替え用）
     * @return 低解像度プレビュー画像
     */
    private func decodeIncrementalJPEG(data: Data, plan: DownsamplePlan, index: Int) -> NSImage? {
        // 低解像度プレビューの目標サイズ
        let previewMax = max(incrementalPreviewMinPixels, plan.maxPixel / 2)
        let previewSubsample: Int?
        if let originalMax = plan.originalPixelMax {
            previewSubsample = determineSubsampleFactor(originalMax: originalMax, targetMax: CGFloat(previewMax))
        } else {
            previewSubsample = nil
        }

        // データの一部を使用してプレビューを生成
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

        // 全データを使用する高解像度デコードをバックグラウンドでスケジュール
        if chunkSize < data.count {
            scheduleHighResolutionUpdate(for: index, data: data)
        }

        return NSImage(cgImage: cgPreview, size: NSSize(width: cgPreview.width, height: cgPreview.height))
    }

    /**
     * 段階的JPEGデコードを使用すべきかを判定する
     *
     * 判定条件：
     * 1. JPEG形式であること
     * 2. 元画像サイズが目標サイズの1.5倍以上であること
     *
     * @param source 画像ソース
     * @param plan ダウンサンプリング計画
     * @return 段階的デコードを使用すべき場合true
     */
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
        // 元画像が目標サイズの1.5倍以上の場合に段階的デコードを使用
        return originalMax > CGFloat(plan.maxPixel) * 1.5
    }

    /**
     * 高解像度画像への差し替えをスケジュールする
     *
     * 段階的デコードの第2段階として、全データを使用した高解像度画像を
     * バックグラウンドでデコードし、完了後にキャッシュを更新
     * 現在表示中のページの場合は、通知を送信してUIを更新
     *
     * @param index 画像のインデックス
     * @param data 完全な画像データ
     */
    private func scheduleHighResolutionUpdate(for index: Int, data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 既にタスクが存在する場合はスキップ
            guard self.pendingHighResTasks[index] == nil else { return }
            var workItemReference: DispatchWorkItem?
            let workItem = DispatchWorkItem(qos: .userInitiated) { [weak self] in
                guard let self else { return }
                guard workItemReference?.isCancelled != true else {
                    self.completeHighResTask(for: index)
                    return
                }
                // 全データを使用してデコード
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
                    // キャッシュを更新
                    self.cacheImage(finalImage, at: index)
                    // 現在表示中のページの場合はUIを更新
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

    /**
     * ダウンサンプリング計画を構築する
     *
     * 画像のメタデータから元サイズを取得し、表示サイズに合わせた
     * 最適なダウンサンプリング設定を決定
     *
     * @param source 画像ソース
     * @return ダウンサンプリング計画、不要な場合はnil
     */
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
        // 元画像が目標サイズとほぼ同じ場合はダウンサンプリング不要
        guard originalMax > skipThreshold else { return nil }

        let subsample = determineSubsampleFactor(originalMax: originalMax, targetMax: CGFloat(targetMax))
        return DownsamplePlan(maxPixel: targetMax, subsampleFactor: subsample, originalPixelMax: originalMax)
    }

    /**
     * 表示に必要な最大ピクセル長を計算する
     *
     * ウィンドウサイズに基づいて計算し、オーバースキャン率（1.2倍）を適用
     * これにより、拡大表示時にも十分な画質を確保
     *
     * @return 目標最大ピクセル長
     */
    private func desiredDisplayMaxPixelLength() -> Int {
        if targetDisplaySize.width > 0, targetDisplaySize.height > 0 {
            let maxSide = max(targetDisplaySize.width, targetDisplaySize.height) * downsampleOverscanRatio
            return max(1, Int(ceil(maxSide)))
        }
        // フォールバック：4K相当
        return fallbackMaxDisplayPixels
    }

    /**
     * サブサンプルファクターを決定する
     *
     * JPEGのサブサンプリング（8x8ブロック単位の間引き）を使用して
     * 高速なダウンサンプリングを実現
     *
     * @param originalMax 元画像の最大辺
     * @param targetMax 目標最大辺
     * @return サブサンプルファクター（2, 4, 8）、不要な場合はnil
     */
    private func determineSubsampleFactor(originalMax: CGFloat, targetMax: CGFloat) -> Int? {
        guard originalMax > targetMax, targetMax > 0 else { return nil }
        let ratio = originalMax / targetMax
        if ratio >= 7.0 { return 8 }
        if ratio >= 3.5 { return 4 }
        if ratio >= 1.8 { return 2 }
        return nil
    }
}

/**
 * ダウンサンプリング計画
 *
 * 画像デコード時のダウンサンプリング設定を保持
 */
private struct DownsamplePlan {
    /// 目標最大ピクセル長
    let maxPixel: Int
    /// サブサンプルファクター（2, 4, 8のいずれか）
    let subsampleFactor: Int?
    /// 元画像の最大辺長
    let originalPixelMax: CGFloat?
}

/**
 * プリロード計画
 *
 * 段階的プリロードの計画を保持
 * Primary完了後、順次Additionalチャンクが実行される
 */
private struct PreloadPlan {
    /// Primary段階でプリロードするインデックス（最優先）
    let primaryOffsets: [Int]
    /// Additional段階でプリロードするインデックスのチャンク（順次実行）
    let additionalChunks: [[Int]]
}

/**
 * 通知名の拡張
 *
 * ImageManagerからの画像更新通知を定義
 */
extension Notification.Name {
    /// 画像が更新されたことを通知（高解像度差し替え時など）
    static let imageManagerDidUpdateImage = Notification.Name("com.dmng.CoverZip.imageManagerDidUpdateImage")
}

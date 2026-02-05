//
//  PrerenderedLayerCache.swift
//  coverZipViewer
//
//  Created by Claude on 2025.
//

import Foundation
import AppKit
import QuartzCore

/**
 * GPU事前レンダリング済みCALayerのキャッシュ管理クラス
 *
 * NSImageからCGImageを取得し、CALayerのcontentsに設定することで
 * GPUへのテクスチャアップロードを事前に完了させる。
 * これにより、ページ切り替え時の表示遅延を大幅に削減する。
 */
class PrerenderedLayerCache {

    /// キャッシュされた事前レンダリング済みレイヤー情報
    private struct CachedLayer {
        let layer: CALayer
        let size: CGSize
        let accessTime: Date
    }

    /// インデックスごとのレイヤーキャッシュ
    private var layerCache: [Int: CachedLayer] = [:]

    /// 見開き用のペアレイヤーキャッシュ（left, right）
    private var spreadLayerCache: [Int: (left: CALayer?, right: CALayer?)] = [:]

    /// 最大キャッシュサイズ（単ページ）
    private let maxCacheSize: Int = 5

    /// 最大見開きキャッシュサイズ
    private let maxSpreadCacheSize: Int = 3

    /// 現在のページインデックス（LRU計算用）
    private var currentIndex: Int = 0

    /// ターゲット表示サイズ
    private var targetDisplaySize: CGSize = .zero

    /// キャッシュアクセス用のシリアルキュー
    private let cacheQueue = DispatchQueue(label: "com.coverzip.prerenderedlayercache", qos: .userInitiated)

    // MARK: - Public Methods

    /**
     * ターゲット表示サイズを設定
     *
     * @param size 表示対象の最大サイズ
     */
    func setTargetDisplaySize(_ size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }

        if targetDisplaySize != size {
            targetDisplaySize = size
            // サイズ変更時はキャッシュをクリア
            clearAllCache()
            NSLog("[PrerenderedLayerCache] Target size updated to \(Int(size.width))x\(Int(size.height))")
        }
    }

    /**
     * 現在のページインデックスを設定（LRU計算用）
     *
     * @param index 現在のページインデックス
     */
    func setCurrentIndex(_ index: Int) {
        currentIndex = index
    }

    /**
     * 指定インデックスの事前レンダリング済みレイヤーを取得
     *
     * @param index ページインデックス
     * @return キャッシュされたCALayer、なければnil
     */
    func getPrerenderedLayer(for index: Int) -> CALayer? {
        return cacheQueue.sync {
            if let cached = layerCache[index] {
                // アクセス時間を更新
                layerCache[index] = CachedLayer(
                    layer: cached.layer,
                    size: cached.size,
                    accessTime: Date()
                )
                return cached.layer
            }
            return nil
        }
    }

    /**
     * 見開き用の事前レンダリング済みレイヤーペアを取得
     *
     * @param index ページインデックス
     * @return (左レイヤー, 右レイヤー)のタプル、なければnil
     */
    func getSpreadLayers(for index: Int) -> (left: CALayer?, right: CALayer?)? {
        return cacheQueue.sync {
            return spreadLayerCache[index]
        }
    }

    /**
     * NSImageから事前レンダリング済みレイヤーを作成してキャッシュ
     *
     * @param image ソース画像
     * @param index ページインデックス
     * @param completion 完了時コールバック（メインスレッドで呼ばれる）
     */
    func prerenderLayer(from image: NSImage, for index: Int, completion: ((CALayer?) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            // CGImageを取得
            guard let cgImage = self.extractCGImage(from: image) else {
                NSLog("[PrerenderedLayerCache] Failed to extract CGImage for index \(index)")
                DispatchQueue.main.async { completion?(nil) }
                return
            }

            // レイヤーサイズを計算（アスペクト比を維持）
            let layerSize = self.calculateLayerSize(for: cgImage)

            // メインスレッドでCALayerを作成・設定
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    completion?(nil)
                    return
                }

                let layer = self.createPrerenderedLayer(cgImage: cgImage, size: layerSize)

                // キャッシュに追加
                self.cacheQueue.async {
                    self.addToCache(layer: layer, size: layerSize, for: index)
                }

                NSLog("[PrerenderedLayerCache] Prerendered layer for index \(index), size: \(Int(layerSize.width))x\(Int(layerSize.height))")
                completion?(layer)
            }
        }
    }

    /**
     * 見開き用の事前レンダリング済みレイヤーペアを作成してキャッシュ
     *
     * @param leftImage 左ページ画像
     * @param rightImage 右ページ画像
     * @param index ページインデックス
     * @param completion 完了時コールバック
     */
    func prerenderSpreadLayers(leftImage: NSImage?, rightImage: NSImage?, for index: Int, completion: (((left: CALayer?, right: CALayer?)) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?((nil, nil)) }
                return
            }

            let leftCGImage = leftImage.flatMap { self.extractCGImage(from: $0) }
            let rightCGImage = rightImage.flatMap { self.extractCGImage(from: $0) }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    completion?((nil, nil))
                    return
                }

                var leftLayer: CALayer?
                var rightLayer: CALayer?

                if let cg = leftCGImage {
                    let size = self.calculateLayerSize(for: cg, halfWidth: true)
                    leftLayer = self.createPrerenderedLayer(cgImage: cg, size: size)
                }

                if let cg = rightCGImage {
                    let size = self.calculateLayerSize(for: cg, halfWidth: true)
                    rightLayer = self.createPrerenderedLayer(cgImage: cg, size: size)
                }

                // キャッシュに追加
                self.cacheQueue.async {
                    self.addSpreadToCache(left: leftLayer, right: rightLayer, for: index)
                }

                NSLog("[PrerenderedLayerCache] Prerendered spread layers for index \(index)")
                completion?((leftLayer, rightLayer))
            }
        }
    }

    /**
     * 指定インデックスがキャッシュに存在するか確認
     *
     * @param index ページインデックス
     * @return キャッシュに存在すればtrue
     */
    func hasPrerenderedLayer(for index: Int) -> Bool {
        return cacheQueue.sync {
            return layerCache[index] != nil
        }
    }

    /**
     * 見開きキャッシュが存在するか確認
     *
     * @param index ページインデックス
     * @return キャッシュに存在すればtrue
     */
    func hasSpreadLayers(for index: Int) -> Bool {
        return cacheQueue.sync {
            return spreadLayerCache[index] != nil
        }
    }

    /**
     * 全キャッシュをクリア
     */
    func clearAllCache() {
        cacheQueue.async { [weak self] in
            self?.layerCache.removeAll()
            self?.spreadLayerCache.removeAll()
            NSLog("[PrerenderedLayerCache] All cache cleared")
        }
    }

    /**
     * 現在ページ以外のキャッシュをクリア（メモリ圧迫時用）
     */
    func clearCacheExceptCurrent() {
        cacheQueue.async { [weak self] in
            guard let self = self else { return }

            let currentLayer = self.layerCache[self.currentIndex]
            self.layerCache.removeAll()
            if let layer = currentLayer {
                self.layerCache[self.currentIndex] = layer
            }

            let currentSpread = self.spreadLayerCache[self.currentIndex]
            self.spreadLayerCache.removeAll()
            if let spread = currentSpread {
                self.spreadLayerCache[self.currentIndex] = spread
            }

            NSLog("[PrerenderedLayerCache] Cache cleared except current index \(self.currentIndex)")
        }
    }

    // MARK: - Private Methods

    /**
     * NSImageからCGImageを抽出
     */
    private func extractCGImage(from image: NSImage) -> CGImage? {
        // 方法1: cgImage(forProposedRect:context:hints:)を使用
        var rect = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cgImage
        }

        // 方法2: NSBitmapImageRepから取得
        if let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData) {
            return bitmapRep.cgImage
        }

        // 方法3: representationsから直接取得
        for rep in image.representations {
            if let bitmapRep = rep as? NSBitmapImageRep,
               let cgImage = bitmapRep.cgImage {
                return cgImage
            }
        }

        return nil
    }

    /**
     * 表示サイズに合わせたレイヤーサイズを計算（アスペクト比維持）
     */
    private func calculateLayerSize(for cgImage: CGImage, halfWidth: Bool = false) -> CGSize {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        guard imageWidth > 0 && imageHeight > 0 else {
            return CGSize(width: 100, height: 100)
        }

        var targetWidth = targetDisplaySize.width
        let targetHeight = targetDisplaySize.height

        // 見開きの場合は半分の幅で計算
        if halfWidth {
            targetWidth = targetWidth / 2
        }

        guard targetWidth > 0 && targetHeight > 0 else {
            return CGSize(width: imageWidth, height: imageHeight)
        }

        // アスペクト比を維持してフィット
        let imageAspect = imageWidth / imageHeight
        let targetAspect = targetWidth / targetHeight

        var resultWidth: CGFloat
        var resultHeight: CGFloat

        if imageAspect > targetAspect {
            // 画像が横長: 幅に合わせる
            resultWidth = targetWidth
            resultHeight = targetWidth / imageAspect
        } else {
            // 画像が縦長: 高さに合わせる
            resultHeight = targetHeight
            resultWidth = targetHeight * imageAspect
        }

        return CGSize(width: resultWidth, height: resultHeight)
    }

    /**
     * 事前レンダリング済みCALayerを作成
     */
    private func createPrerenderedLayer(cgImage: CGImage, size: CGSize) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contents = cgImage
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // 高品質フィルタリング
        layer.minificationFilter = .trilinear
        layer.magnificationFilter = .linear

        // GPUへのアップロードを強制
        // setNeedsDisplay() + displayIfNeeded() でテクスチャを事前にGPUに転送
        layer.setNeedsDisplay()
        layer.displayIfNeeded()

        return layer
    }

    /**
     * キャッシュに追加（LRU管理）
     */
    private func addToCache(layer: CALayer, size: CGSize, for index: Int) {
        // キャッシュサイズ制限チェック
        if layerCache.count >= maxCacheSize && layerCache[index] == nil {
            evictOldestLayer()
        }

        layerCache[index] = CachedLayer(
            layer: layer,
            size: size,
            accessTime: Date()
        )
    }

    /**
     * 見開きキャッシュに追加
     */
    private func addSpreadToCache(left: CALayer?, right: CALayer?, for index: Int) {
        // キャッシュサイズ制限チェック
        if spreadLayerCache.count >= maxSpreadCacheSize && spreadLayerCache[index] == nil {
            evictOldestSpreadLayer()
        }

        spreadLayerCache[index] = (left, right)
    }

    /**
     * 最も古い（現在位置から遠い）レイヤーを削除
     */
    private func evictOldestLayer() {
        guard !layerCache.isEmpty else { return }

        // 現在のインデックスから最も遠いものを削除
        let farthestIndex = layerCache.keys.max { abs($0 - currentIndex) < abs($1 - currentIndex) }
        if let indexToRemove = farthestIndex {
            layerCache.removeValue(forKey: indexToRemove)
            NSLog("[PrerenderedLayerCache] Evicted layer at index \(indexToRemove)")
        }
    }

    /**
     * 最も古い見開きレイヤーを削除
     */
    private func evictOldestSpreadLayer() {
        guard !spreadLayerCache.isEmpty else { return }

        let farthestIndex = spreadLayerCache.keys.max { abs($0 - currentIndex) < abs($1 - currentIndex) }
        if let indexToRemove = farthestIndex {
            spreadLayerCache.removeValue(forKey: indexToRemove)
            NSLog("[PrerenderedLayerCache] Evicted spread layers at index \(indexToRemove)")
        }
    }
}

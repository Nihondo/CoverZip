//
//  ImageIOOptions.swift
//  Shared helpers for ImageIO decode/cache policies
//

import Foundation
import ImageIO

/// 画像デコードキャッシュの方針
public enum CZImageDecodeCachePolicy: String {
    /// キャッシュしない（QuickLookサムネイルなど単発描画に最適）
    case noCache
    /// キャッシュするが即時デコードはしない（初回描画時にデコード）
    case deferred
    /// 読み込み時に即デコードしてキャッシュ（初回表示も滑らか）
    case immediate
}

public enum CZImageIOOptionsBuilder {
    /// サムネイル生成向けのオプション辞書を生成
    public static func buildThumbnailOptions(maxPixels: Int, cachePolicy: CZImageDecodeCachePolicy) -> CFDictionary {
        return buildDownsampleOptions(maxPixels: maxPixels, cachePolicy: cachePolicy, subsampleFactor: nil)
    }

    /// ダウンサンプリング（部分的デコード）向けのオプション辞書を生成
    public static func buildDownsampleOptions(maxPixels: Int,
                                              cachePolicy: CZImageDecodeCachePolicy,
                                              subsampleFactor: Int?) -> CFDictionary {
        var dict: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixels)
        ]

        if let factor = subsampleFactor, factor > 1 {
            if #available(macOS 10.15, *) {
                dict[kCGImageSourceSubsampleFactor] = min(8, max(1, factor))
            }
        }

        applyCachePolicy(cachePolicy, into: &dict)
        return dict as CFDictionary
    }

    /// 通常の `CGImageSourceCreateImageAtIndex` 用オプション辞書
    public static func buildDecodeOptions(cachePolicy: CZImageDecodeCachePolicy) -> CFDictionary? {
        var dict: [CFString: Any] = [:]
        applyCachePolicy(cachePolicy, into: &dict)
        return dict as CFDictionary
    }

    private static func applyCachePolicy(_ policy: CZImageDecodeCachePolicy, into dict: inout [CFString: Any]) {
        switch policy {
        case .noCache:
            dict[kCGImageSourceShouldCache] = false
            dict[kCGImageSourceShouldCacheImmediately] = false
        case .deferred:
            dict[kCGImageSourceShouldCache] = true
            dict[kCGImageSourceShouldCacheImmediately] = false
        case .immediate:
            dict[kCGImageSourceShouldCache] = true
            dict[kCGImageSourceShouldCacheImmediately] = true
        }
    }
}

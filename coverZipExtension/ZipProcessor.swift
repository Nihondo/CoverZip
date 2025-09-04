//
//  ZipProcessor.swift
//  coverZipExtension
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation
import CoreGraphics

/**
 * ZIPファイルの処理を担当するクラス
 * ZIPファイルの解析、画像ファイルの検索・抽出機能を提供する
 */
class ZipProcessor {
    
    /**
     * ZIPファイルから最初の画像ファイルを抽出する
     * 
     * @param url ZIPファイルのURL
     * @return 画像データ（見つからない場合はnil）
     */
    static func extractFirstImageFromZip(at url: URL) -> Data? {
        return CZZip.firstImageData(from: url)
    }

    /**
     * ZIPファイルから最初の画像ファイルを抽出する（ゼロ埋め"1"優先の早期判定オプション）
     *
     * @param url ZIPファイルのURL
     * @param isZeroPaddedFirstPreferred 先頭判定としてベース名が 01/001/0001... に一致する最初の画像を優先する
     * @return 画像データ（見つからない場合はnil）
     */
    static func extractFirstImageFromZip(at url: URL, isZeroPaddedFirstPreferred: Bool) -> Data? {
        return CZZip.firstImageData(from: url, isZeroPaddedFirstPreferred: isZeroPaddedFirstPreferred)
    }

    /**
     * オプション指定で先頭画像を抽出する（ヒューリスティクス+自然順フォールバック）
     *
     * @param url ZIPファイルのURL
     * @param options 先頭判定オプション（例: [.preferZeroPaddedOne, .preferCoverLike]）
     * @return 画像データ（見つからない場合はnil）
     */
    static func extractFirstImageFromZip(at url: URL, options: CZFirstImageOptions) -> Data? {
        return CZZip.firstImageData(from: url, options: options)
    }

    /**
     * ストリーミング展開 + ImageIO増分デコードでサムネイル(CGImage)を生成
     * - 優先: 表紙らしさ > 0埋め1 > 自然順
     */
    static func extractFirstImageThumbnail(at url: URL, options: CZFirstImageOptions, maxPixel: Int) -> CGImage? {
        return CZZip.firstImageThumbnail(from: url, options: options, maxPixel: maxPixel)
    }
    
    /**
     * ZIPファイルから全ての画像ファイルを抽出する
     * 
     * @param url ZIPファイルのURL
     * @return 画像エントリの配列（見つからない場合は空配列）
     */
    static func extractAllImagesFromZip(at url: URL) -> [ImageEntry] {
        return CZZip.imageEntries(from: url).map { ImageEntry(filename: $0.filename, imageData: $0.imageData) }
    }
    
    // 低レベルのZIP処理はShared/CZZipに移管済み
}

// 低レベルのZipEntryはShared/CZZipEntryに集約

/**
 * ZIPファイル内の画像エントリを表す構造体
 */
struct ImageEntry {
    let filename: String           // ファイル名
    let imageData: Data           // 画像データ
}

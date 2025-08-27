//
//  ZipProcessor.swift
//  coverZipExtension
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation

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
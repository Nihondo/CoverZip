//
//  ImageFileFilter.swift
//  画像パス判定の共有ユーティリティ
//

import Foundation

public enum ImageFileFilter {
    private static let imageExtensions: [String] = [
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif", ".ico", ".icns", ".webp"
    ]

    /// 対応画像ファイルらしいパスかどうかを判定する。
    /// 判定ルール:
    /// - `__MACOSX` フォルダ配下は除外
    /// - 隠しファイル（ベース名が `.` で始まる）は除外
    /// - 既知の画像拡張子のみ許可（大文字小文字は無視）
    public static func isImagePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if lower.contains("__macosx") { return false }
        let basename = (path as NSString).lastPathComponent
        if basename.hasPrefix(".") { return false }
        return imageExtensions.contains { lower.hasSuffix($0) }
    }
}

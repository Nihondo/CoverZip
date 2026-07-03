//
//  ArchiveKind.swift
//  CoverZip
//
//  ZIP/RAR 系アーカイブの軽量判定ユーティリティ
//

import Foundation

/// CoverZip が画像アーカイブとして扱うコンテナ種別。
public enum CZArchiveKind {
    case zip
    case rar

    public static let zipExtensions: Set<String> = ["zip", "cbz"]
    public static let rarExtensions: Set<String> = ["rar", "cbr"]
    public static let supportedFileExtensions = ["zip", "cbz", "rar", "cbr"]

    /// URL の拡張子だけでアーカイブ種別を判定する。
    public static func kind(forExtensionOf url: URL) -> CZArchiveKind? {
        let ext = url.pathExtension.lowercased()
        if zipExtensions.contains(ext) { return .zip }
        if rarExtensions.contains(ext) { return .rar }
        return nil
    }

    /// ファイル先頭のマジックナンバーを優先してアーカイブ種別を判定する。
    ///
    /// `.cbr` は実体が ZIP の場合もあるため、展開直前は拡張子より実データを優先する。
    /// 先頭バイトを読めない場合や判別できない場合は拡張子判定へフォールバックする。
    public static func detect(at url: URL) -> CZArchiveKind? {
        if let data = readHeaderBytes(at: url), let kind = kind(forMagicHeader: data) {
            return kind
        }
        return kind(forExtensionOf: url)
    }

    private static func readHeaderBytes(at url: URL) -> Data? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            return try handle.read(upToCount: 8)
        } catch {
            return nil
        }
    }

    private static func kind(forMagicHeader data: Data) -> CZArchiveKind? {
        let bytes = [UInt8](data)
        if bytes.count >= 2, bytes[0] == 0x50, bytes[1] == 0x4b {
            return .zip
        }
        if bytes.count >= 6,
           bytes[0] == 0x52, bytes[1] == 0x61, bytes[2] == 0x72,
           bytes[3] == 0x21, bytes[4] == 0x1a, bytes[5] == 0x07 {
            return .rar
        }
        return nil
    }
}

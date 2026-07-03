//
//  RarCore.swift
//  CoverZip
//
//  Unrar.swift を利用した RAR 画像抽出ユーティリティ
//

import Foundation
import Unrar

/// RAR 内画像エントリのメタデータ。
public struct CZRarImageEntryInfo {
    public let filename: String
    let entry: Entry
}

/// RAR アーカイブから画像メタデータと画像データを読み込む。
public enum CZRar {
    /// Quick Look 拡張内での過大展開を防ぐため、1画像の展開後サイズに上限を設ける。
    public static let maxExtractedImageBytes = 256 * 1024 * 1024

    /// RAR ファイル URL から画像エントリのメタデータを読み込む。
    public static func imageEntryInfoList(from url: URL) -> [CZRarImageEntryInfo] {
        do {
            let archive = try Archive(fileURL: url)
            let entries = try archive.entries()
            let imageEntries = entries.compactMap { entry -> CZRarImageEntryInfo? in
                guard !entry.directory else { return nil }
                guard !entry.encrypted else {
                    NSLog("CZRar encrypted entry skipped: %@", entry.fileName)
                    return nil
                }
                guard entry.uncompressedSize <= UInt64(maxExtractedImageBytes) else {
                    NSLog("CZRar oversized entry skipped: %@ (%llu bytes)", entry.fileName, entry.uncompressedSize)
                    return nil
                }
                let normalizedFilename = normalizePath(entry.fileName)
                guard ImageFileFilter.isImagePath(normalizedFilename) else { return nil }
                return CZRarImageEntryInfo(filename: normalizedFilename, entry: entry)
            }
            return sortEntriesByNaturalFilename(imageEntries)
        } catch {
            NSLog("CZRar read error: %@", String(describing: error))
            return []
        }
    }

    /// 指定された RAR エントリの画像データを読み込む。
    public static func extractImageData(from url: URL, entryInfo: CZRarImageEntryInfo) -> Data? {
        guard entryInfo.entry.uncompressedSize <= UInt64(maxExtractedImageBytes) else {
            NSLog("CZRar extraction skipped for oversized entry: %@ (%llu bytes)", entryInfo.filename, entryInfo.entry.uncompressedSize)
            return nil
        }

        do {
            let archive = try Archive(fileURL: url)
            return try archive.extract(entryInfo.entry)
        } catch {
            NSLog("CZRar extract error: %@ (%@)", entryInfo.filename, String(describing: error))
            return nil
        }
    }

    /// RAR ファイル URL から表紙候補のサムネイルを生成する。
    public static func firstImageThumbnail(from url: URL, options: CZFirstImageOptions, maxPixel: Int) -> CZFirstImageThumbnailResult {
        let entries = imageEntryInfoList(from: url)
        guard let selectedIndex = CZCoverSelector.selectIndex(filenames: entries.map(\.filename), options: options) else {
            return .none
        }
        guard let data = extractImageData(from: url, entryInfo: entries[selectedIndex]) else {
            return .none
        }
        if let thumbnail = CZCoverSelector.thumbnail(fromImageData: data, maxPixel: maxPixel) {
            return .thumbnail(thumbnail)
        }
        return .rawData(data)
    }

    private static func normalizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    private static func sortEntriesByNaturalFilename(_ entries: [CZRarImageEntryInfo]) -> [CZRarImageEntryInfo] {
        entries
            .map { entry -> (CZRarImageEntryInfo, NaturalSort.NaturalSortKey, NaturalSort.NaturalSortKey) in
                let lastComponent = (entry.filename as NSString).lastPathComponent
                return (entry, NaturalSort.NaturalSortKey(lastComponent), NaturalSort.NaturalSortKey(entry.filename))
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.2 < rhs.2
            }
            .map { $0.0 }
    }
}

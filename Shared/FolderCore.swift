//
//  FolderCore.swift
//  CoverZip で共有するフォルダ列挙ユーティリティ（ZipCore.swift と対）
//

import Foundation

/// フォルダ内の画像1件分の情報（CZImageEntryInfo のフォルダ版相当）
public struct CZFolderImageEntry {
    public let relativePath: String
    public let fileURL: URL
}

public enum CZFolder {
    /// rootURL 以下を再帰列挙し、画像のみを自然順で返す。
    /// ソートキーは ZIP と同じ lastPathComponent 基準の自然順を第1キーとし、
    /// 別サブフォルダ間で同名ファイルが衝突しても順序が決定的になるよう相対パス全体を第2キー（タイブレーク）にする。
    public static func imageEntryList(from rootURL: URL) -> [CZFolderImageEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let rootPath = rootURL.standardizedFileURL.path
        var entries: [CZFolderImageEntry] = []
        for case let fileURL as URL in enumerator {
            guard let isRegular = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegular else { continue }
            let path = fileURL.standardizedFileURL.path
            let relativePath = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : path
            guard ImageFileFilter.isImagePath(relativePath) else { continue }
            entries.append(CZFolderImageEntry(relativePath: relativePath, fileURL: fileURL))
        }

        return entries
            .map { entry -> (CZFolderImageEntry, NaturalSort.NaturalSortKey, NaturalSort.NaturalSortKey) in
                let lastComponent = (entry.relativePath as NSString).lastPathComponent
                return (entry, NaturalSort.NaturalSortKey(lastComponent), NaturalSort.NaturalSortKey(entry.relativePath))
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.2 < rhs.2
            }
            .map { $0.0 }
    }

    /// 遅延ロード用の画像データ読み込み（失敗時は nil）。
    public static func imageData(for entry: CZFolderImageEntry) -> Data? {
        return try? Data(contentsOf: entry.fileURL, options: [.mappedIfSafe])
    }
}

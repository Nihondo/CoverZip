//
//  ImageEntrySource.swift
//  coverZipViewer
//
//  ImageManager が扱う画像データソース（ZIP / フォルダ）の抽象化
//

import Foundation

/// ImageManager が遅延ロードで参照する画像エントリ集合の抽象。
/// ZIP・フォルダのどちらから読み込んだ場合も同一のインデックスベースAPIで扱えるようにする。
protocol ImageEntrySource {
    var count: Int { get }
    /// エントリ名（ZIP: エントリ内パス／フォルダ: ルートからの相対パス）
    func filename(at index: Int) -> String
    /// 画像の生データを読み込む（decodeQueue/tinyDecodeQueue から呼ばれる想定）
    func imageData(at index: Int) -> Data?
}

/// ZIPアーカイブを画像データソースとして扱う。
struct ZipImageEntrySource: ImageEntrySource {
    let zipData: Data
    let entries: [CZImageEntryInfo]

    var count: Int { entries.count }

    func filename(at index: Int) -> String { entries[index].filename }

    func imageData(at index: Int) -> Data? {
        CZZip.extractImageData(from: zipData, entryInfo: entries[index])
    }
}

/// RARアーカイブを画像データソースとして扱う。
struct RarImageEntrySource: ImageEntrySource {
    let fileURL: URL
    let entries: [CZRarImageEntryInfo]

    var count: Int { entries.count }

    func filename(at index: Int) -> String { entries[index].filename }

    func imageData(at index: Int) -> Data? {
        CZRar.extractImageData(from: fileURL, entryInfo: entries[index])
    }
}

/// フォルダ（サブフォルダ再帰含む）を画像データソースとして扱う。
struct FolderImageEntrySource: ImageEntrySource {
    let entries: [CZFolderImageEntry]

    var count: Int { entries.count }

    func filename(at index: Int) -> String { entries[index].relativePath }

    func imageData(at index: Int) -> Data? {
        CZFolder.imageData(for: entries[index])
    }
}

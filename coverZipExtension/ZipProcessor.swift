//
//  ZipProcessor.swift
//  coverZipExtension
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation
import Compression

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
        do {
            let data = try Data(contentsOf: url)
            return parseZipAndFindFirstImage(data: data)
        } catch {
            NSLog("Error reading ZIP file: \(error)")
            return nil
        }
    }
    
    /**
     * ZIPファイルから全ての画像ファイルを抽出する
     * 
     * @param url ZIPファイルのURL
     * @return 画像エントリの配列（見つからない場合は空配列）
     */
    static func extractAllImagesFromZip(at url: URL) -> [ImageEntry] {
        do {
            let data = try Data(contentsOf: url)
            return parseZipAndFindAllImages(data: data)
        } catch {
            NSLog("Error reading ZIP file: \(error)")
            return []
        }
    }
    
    /**
     * ZIPファイルデータを解析し、最初の画像ファイルを検索する
     * 
     * @param data ZIPファイルのバイナリデータ
     * @return 最初に見つかった画像ファイルのデータ（見つからない場合はnil）
     */
    private static func parseZipAndFindFirstImage(data: Data) -> Data? {
        // ZIP Central Directory の検索
        guard let centralDirectoryOffset = findCentralDirectoryOffset(in: data) else {
            return nil
        }

        // Central Directory からファイルエントリを読み取り
        let entries = parseCentralDirectory(data: data, offset: centralDirectoryOffset)

        // 画像ファイルのみ抽出し、ファイル名の自然順（数字は数値として比較）でソート
        let imageEntries = entries
            .filter { isImageFile(filename: $0.filename) }
            .sorted { a, b in
                naturalLess((a.filename as NSString).lastPathComponent,
                            (b.filename as NSString).lastPathComponent)
            }

        // 先頭（自然順の最初）の画像を展開
        if let first = imageEntries.first {
            return extractFileData(data: data, entry: first)
        }

        return nil
    }
    
    /**
     * ZIPファイルデータを解析し、全ての画像ファイルを検索する
     * 
     * @param data ZIPファイルのバイナリデータ
     * @return 全ての画像ファイルのエントリ配列
     */
    private static func parseZipAndFindAllImages(data: Data) -> [ImageEntry] {
        // ZIP Central Directory の検索
        guard let centralDirectoryOffset = findCentralDirectoryOffset(in: data) else {
            return []
        }
        
        // Central Directory からファイルエントリを読み取り
        let entries = parseCentralDirectory(data: data, offset: centralDirectoryOffset)
        
        // まず画像ファイルのみ抽出し、ファイル名の自然順でソートしてから展開
        let imageFileEntries = entries
            .filter { isImageFile(filename: $0.filename) }
            .sorted { a, b in
                naturalLess((a.filename as NSString).lastPathComponent,
                            (b.filename as NSString).lastPathComponent)
            }

        var imageEntries: [ImageEntry] = []
        for entry in imageFileEntries {
            if let imageData = extractFileData(data: data, entry: entry) {
                imageEntries.append(ImageEntry(filename: entry.filename, imageData: imageData))
            }
        }

        return imageEntries
    }
    
    /**
     * ZIPファイル内のCentral Directoryの位置を検索する
     * End of Central Directory Record（EOCDR）から逆算して位置を特定
     * 
     * @param data ZIPファイルのバイナリデータ
     * @return Central Directoryの開始オフセット（見つからない場合はnil）
     */
    private static func findCentralDirectoryOffset(in data: Data) -> Int? {
        // End of Central Directory Record の検索 (0x06054b50)
        let eocdrSignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        
        // ファイルの最後から検索
        let searchRange = max(0, data.count - 65536)
        for i in stride(from: data.count - 4, through: searchRange, by: -1) {
            if data.subdata(in: i..<i+4).elementsEqual(eocdrSignature) {
                // Central Directory のオフセットを取得 (16バイト後)
                let offsetBytes = data.subdata(in: i+16..<i+20)
                let offset = offsetBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
                return Int(offset)
            }
        }
        
        return nil
    }
    
    /**
     * Central Directoryを解析してファイルエントリのリストを作成する
     * 
     * @param data ZIPファイルのバイナリデータ
     * @param offset Central Directoryの開始オフセット
     * @return ZIPファイル内のファイルエントリのリスト
     */
    private static func parseCentralDirectory(data: Data, offset: Int) -> [ZipEntry] {
        var entries: [ZipEntry] = []
        var currentOffset = offset
        
        while currentOffset < data.count - 4 {
            // Central Directory File Header の署名をチェック (0x02014b50)
            let signature = data.subdata(in: currentOffset..<currentOffset+4)
            let expectedSignature: [UInt8] = [0x50, 0x4b, 0x01, 0x02]
            
            if !signature.elementsEqual(expectedSignature) {
                break
            }
            
            // GP Flag / Compression Method / Sizes（Central Directory）
            let gpFlag = data.subdata(in: currentOffset+8..<currentOffset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compMethod = data.subdata(in: currentOffset+10..<currentOffset+12).withUnsafeBytes { $0.load(as: UInt16.self) }
            let cdCompressed = data.subdata(in: currentOffset+20..<currentOffset+24).withUnsafeBytes { $0.load(as: UInt32.self) }

            // ファイル名の長さを取得
            let filenameLength = data.subdata(in: currentOffset+28..<currentOffset+30).withUnsafeBytes { $0.load(as: UInt16.self) }
            let extraFieldLength = data.subdata(in: currentOffset+30..<currentOffset+32).withUnsafeBytes { $0.load(as: UInt16.self) }
            let commentLength = data.subdata(in: currentOffset+32..<currentOffset+34).withUnsafeBytes { $0.load(as: UInt16.self) }
            
            // ファイル名を取得
            let filenameData = data.subdata(in: currentOffset+46..<currentOffset+46+Int(filenameLength))
            let filename = String(data: filenameData, encoding: .utf8) ?? ""
            
            // Local File Header のオフセットを取得
            let localHeaderOffset = data.subdata(in: currentOffset+42..<currentOffset+46).withUnsafeBytes { $0.load(as: UInt32.self) }
            
            entries.append(ZipEntry(filename: filename, localHeaderOffset: Int(localHeaderOffset), compressedSize: Int(cdCompressed), generalPurposeFlag: gpFlag, compressionMethod: compMethod))
            
            // 次のエントリに移動
            currentOffset += 46 + Int(filenameLength) + Int(extraFieldLength) + Int(commentLength)
        }
        
        return entries
    }
    
    /**
     * ファイル名が画像ファイルかどうかを判定する
     * 対応形式: .jpg, .jpeg, .png, .gif, .bmp, .tiff, .tif, .ico, .icns
     * 除外: __MACOSX フォルダ内のファイル、隠しファイル（.で始まる）
     * 
     * @param filename 判定対象のファイル名
     * @return 画像ファイルの場合はtrue、そうでなければfalse
     */
    private static func isImageFile(filename: String) -> Bool {
        let lowercaseFilename = filename.lowercased()
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif", ".ico", ".icns"]
        
        // __MACOSX フォルダは無視
        if lowercaseFilename.contains("__macosx") {
            return false
        }
        
        // 隠しファイルは無視
        if filename.hasPrefix(".") {
            return false
        }
        
        return imageExtensions.contains { lowercaseFilename.hasSuffix($0) }
    }
    
    /**
     * ZIPファイル内の指定されたファイルエントリからデータを抽出する
     * Local File Headerを解析し、圧縮方法に応じて展開処理を行う
     * 
     * @param data ZIPファイルのバイナリデータ
     * @param entry 抽出対象のファイルエントリ
     * @return 展開されたファイルデータ（失敗した場合はnil）
     */
    private static func extractFileData(data: Data, entry: ZipEntry) -> Data? {
        let offset = entry.localHeaderOffset
        
        // Local File Header の署名をチェック (0x04034b50)
        let signature = data.subdata(in: offset..<offset+4)
        let expectedSignature: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
        
        if !signature.elementsEqual(expectedSignature) {
            return nil
        }
        
        // ファイル名の長さと Extra Field の長さを取得
        let filenameLength = data.subdata(in: offset+26..<offset+28).withUnsafeBytes { $0.load(as: UInt16.self) }
        let extraFieldLength = data.subdata(in: offset+28..<offset+30).withUnsafeBytes { $0.load(as: UInt16.self) }
        
    // ローカルヘッダの圧縮サイズ（bit3が立っている場合は0）
    let lhCompressed = data.subdata(in: offset+18..<offset+22).withUnsafeBytes { $0.load(as: UInt32.self) }
        
    // 圧縮方法を取得
    let compressionMethod = data.subdata(in: offset+8..<offset+10).withUnsafeBytes { $0.load(as: UInt16.self) }
        
        // ファイルデータの開始位置
        let fileDataOffset = offset + 30 + Int(filenameLength) + Int(extraFieldLength)
        // 使用する圧縮サイズ（Data Descriptor使用時はCentral Directoryの値）
        let useCompressedSize: Int
        if entry.generalPurposeFlag & 0x0008 != 0 {
            useCompressedSize = entry.compressedSize
        } else {
            useCompressedSize = Int(lhCompressed)
        }
        guard useCompressedSize > 0, fileDataOffset + useCompressedSize <= data.count else { return nil }
        let fileData = data.subdata(in: fileDataOffset..<(fileDataOffset + useCompressedSize))
        
        // 圧縮方法に応じて展開
        if compressionMethod == 0 {
            // 非圧縮
            return fileData
        } else if compressionMethod == 8 {
            // DEFLATE 圧縮
            return inflateData(fileData)
        }
        
        return nil
    }

    // MARK: - Natural sort by filename (numbers compared numerically)
    private enum Token: Equatable {
        case text(String)
        case number(Int, length: Int) // 桁数を保持（同値時の安定化に使用）
    }

    private static func naturalLess(_ lhs: String, _ rhs: String) -> Bool {
        let lt = tokenize(lhs.lowercased())
        let rt = tokenize(rhs.lowercased())
        let n = min(lt.count, rt.count)
        for i in 0..<n {
            let a = lt[i]
            let b = rt[i]
            switch (a, b) {
            case let (.number(x, lx), .number(y, ly)):
                if x != y { return x < y }
                // 数値が同じ場合は桁数の短い方を先に
                if lx != ly { return lx < ly }
            case let (.text(x), .text(y)):
                if x != y { return x < y }
            case (.number, .text):
                // 同一プレフィックス後は数値を先に
                return true
            case (.text, .number):
                return false
            }
        }
        if lt.count != rt.count { return lt.count < rt.count }
        return lhs.localizedCompare(rhs) == .orderedAscending
    }

    private static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch.isNumber {
                var j = i
                while j < s.endIndex, s[j].isNumber { j = s.index(after: j) }
                let substr = String(s[i..<j])
                let val = Int(substr) ?? 0
                tokens.append(.number(val, length: substr.count))
                i = j
            } else {
                var j = i
                while j < s.endIndex, !s[j].isNumber { j = s.index(after: j) }
                let substr = String(s[i..<j])
                tokens.append(.text(substr))
                i = j
            }
        }
        return tokens
    }
    
    /**
     * DEFLATE圧縮されたデータを展開する
     * Apple標準のCompressionフレームワークを使用
     * 
     * @param compressedData 圧縮されたデータ
     * @return 展開されたデータ（失敗した場合はnil）
     */
    private static func inflateData(_ compressedData: Data) -> Data? {
        return compressedData.withUnsafeBytes { bytes in
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 8 * 1024 * 1024) // 8MB buffer
            defer { buffer.deallocate() }
            
            let decompressedSize = compression_decode_buffer(buffer, 8 * 1024 * 1024, bytes.bindMemory(to: UInt8.self).baseAddress!, compressedData.count, nil, COMPRESSION_ZLIB)
            
            if decompressedSize > 0 {
                return Data(bytes: buffer, count: decompressedSize)
            }
            
            return nil
        }
    }
}

/**
 * ZIPファイル内のファイルエントリを表す構造体
 */
struct ZipEntry {
    let filename: String            // ファイル名
    let localHeaderOffset: Int      // Local File Headerのオフセット位置
    let compressedSize: Int         // Central Directory 記載の圧縮サイズ
    let generalPurposeFlag: UInt16  // 汎用フラグ（bit3: データディスクリプタ使用）
    let compressionMethod: UInt16   // 圧縮方式
}

/**
 * ZIPファイル内の画像エントリを表す構造体
 */
struct ImageEntry {
    let filename: String           // ファイル名
    let imageData: Data           // 画像データ
}
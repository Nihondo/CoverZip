//
//  ZipCore.swift
//  CoverZip用共有ZIP解析・展開ユーティリティ
//

import Foundation
import Compression
import ImageIO
import Darwin

public struct CZZipEntry {
    public let filename: String
    public let localHeaderOffset: Int
    public let compressedSize: Int
    public let generalPurposeFlag: UInt16
    public let compressionMethod: UInt16
}

public struct CZImageEntry {
    public let filename: String
    public let imageData: Data
}

/// メタデータのみを持つ軽量な画像エントリ情報（遅延ロード用）
public struct CZImageEntryInfo {
    public let filename: String
    public let entry: CZZipEntry
}

/**
 * ZIPから最初の画像を選択する際のオプション
 *
 * ビット演算で複数のオプションを組み合わせ可能
 */
public struct CZFirstImageOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// ゼロパディングされた "1" を含むファイル名を優先（例：01, 001, image001）
    /// 該当ファイルが見つかった時点で早期に選択
    public static let preferZeroPaddedOne = CZFirstImageOptions(rawValue: 1 << 0)

    /// 表紙らしいファイル名を優先（例："cover", "front", "表紙"、または先頭が00/000/0000）
    public static let preferCoverLike = CZFirstImageOptions(rawValue: 1 << 1)
}

/**
 * CoverZip用ZIP処理ユーティリティ
 *
 * 純SwiftによるZIP解析・展開機能を提供
 * Foundation/Compressionのみを使用し、外部ライブラリに依存しない
 *
 * 主な機能：
 * - Central Directoryの解析
 * - DEFLATE（方式8）および非圧縮（方式0）ファイルの展開
 * - 画像ファイルの自動フィルタリング
 * - 自然順ソート（数値認識）
 * - 遅延ロード対応（メタデータ先行取得）
 *
 * 制約：
 * - Zip64非対応
 * - 暗号化ZIP非対応
 * - 対応圧縮方式：DEFLATE（8）、非圧縮（0）のみ
 */
public enum CZZip {
    /**
     * ZIPデータから全画像エントリを読み込む
     *
     * 処理フロー：
     * 1. Central Directoryを検索・解析
     * 2. 画像ファイルのみをフィルタリング
     * 3. ファイル名の自然順ソート（数値認識）
     * 4. 各画像データを展開
     *
     * @param data ZIPデータ
     * @return 画像エントリの配列（ファイル名とデータ）
     */
    public static func imageEntries(from data: Data) -> [CZImageEntry] {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return [] }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageFiles = entries
            .filter { ImageFileFilter.isImagePath($0.filename) }
            .sorted { a, b in
                NaturalSort.lessFilename((a.filename as NSString).lastPathComponent,
                                          (b.filename as NSString).lastPathComponent)
            }
        var result: [CZImageEntry] = []
        result.reserveCapacity(imageFiles.count)
        for entry in imageFiles {
            if let img = extractFileData(data: data, entry: entry) {
                result.append(CZImageEntry(filename: entry.filename, imageData: img))
            }
        }
        return result
    }

    /**
     * ZIPファイルURLから全画像エントリを読み込む
     *
     * @param url ZIPファイルのURL
     * @return 画像エントリの配列
     */
    public static func imageEntries(from url: URL) -> [CZImageEntry] {
        do { return imageEntries(from: try Data(contentsOf: url, options: [.mappedIfSafe])) }
        catch { NSLog("CZZip read error: \(error)"); return [] }
    }

    /**
     * ZIPデータから全画像エントリのメタデータのみを読み込む（遅延ロード用）
     *
     * 画像データは読み込まず、メタデータ（ファイル名、オフセット等）のみを取得
     * これにより、大量の画像を含むZIPでも即座に一覧取得が可能
     *
     * 用途：
     * - プレビュー表示の高速化（2ページ目以降への即座の移動）
     * - メモリ効率の向上（必要な画像のみを後で読み込む）
     *
     * @param data ZIPデータ
     * @return 画像エントリ情報の配列（データは含まない）
     */
    public static func imageEntryInfoList(from data: Data) -> [CZImageEntryInfo] {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return [] }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageFiles = entries
            .filter { ImageFileFilter.isImagePath($0.filename) }
            .sorted { a, b in
                NaturalSort.lessFilename((a.filename as NSString).lastPathComponent,
                                          (b.filename as NSString).lastPathComponent)
            }
        return imageFiles.map { CZImageEntryInfo(filename: $0.filename, entry: $0) }
    }

    /**
     * ZIPファイルURLから全画像エントリのメタデータを読み込む
     *
     * @param url ZIPファイルのURL
     * @return 画像エントリ情報の配列
     */
    public static func imageEntryInfoList(from url: URL) -> [CZImageEntryInfo] {
        do { return imageEntryInfoList(from: try Data(contentsOf: url, options: [.mappedIfSafe])) }
        catch { NSLog("CZZip read error: \(error)"); return [] }
    }

    /**
     * 特定のエントリ情報から画像データを抽出する
     *
     * imageEntryInfoList()で取得したメタデータから、実際の画像データを展開
     * 遅延ロード方式の第2段階として使用
     *
     * @param zipData ZIPデータ
     * @param entryInfo 画像エントリ情報（imageEntryInfoListで取得）
     * @return 展開された画像データ
     */
    public static func extractImageData(from zipData: Data, entryInfo: CZImageEntryInfo) -> Data? {
        return extractFileData(data: zipData, entry: entryInfo.entry)
    }

    /**
     * ZIPファイルURLから最初の画像データを読み込む（自然順ソート）
     *
     * @param url ZIPファイルのURL
     * @return 最初の画像データ
     */
    public static func firstImageData(from url: URL) -> Data? {
        return imageEntries(from: url).first?.imageData
    }

    /**
     * ZIPファイルURLから最初の画像データを読み込む（早期選択ルール付き）
     *
     * ゼロパディングされた "1" を優先的に選択するオプション付き
     *
     * @param url ZIPファイルのURL
     * @param isZeroPaddedFirstPreferred trueの場合、ゼロパディングされた "1" を含むファイル名を優先
     *        （例：01, 001, image001など）該当ファイルがあればソートせず早期選択、なければ自然順ソートで選択
     * @return 画像データ、見つからない場合はnil
     */
    public static func firstImageData(from url: URL, isZeroPaddedFirstPreferred: Bool) -> Data? {
        do { return firstImageData(from: try Data(contentsOf: url, options: [.mappedIfSafe]), isZeroPaddedFirstPreferred: isZeroPaddedFirstPreferred) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /**
     * ZIPファイルURLから最初の画像データを読み込む（オプションフラグ指定）
     *
     * ヒューリスティック選択 + 自然順ソートフォールバック
     *
     * @param url ZIPファイルのURL
     * @param options 画像選択オプション
     * @return 画像データ、見つからない場合はnil
     */
    public static func firstImageData(from url: URL, options: CZFirstImageOptions) -> Data? {
        do { return firstImageData(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /**
     * ZIPデータから最初の画像データを読み込む（オプションフラグ指定）
     *
     * 優先順位：
     * 1. 表紙らしい名前（"cover", "front", "表紙"、先頭00/000/0000）
     * 2. ゼロパディングされた "1"（01, 001, image001）
     * 3. フォールバック：自然順ソートで最小（ワンパス、全ソート不要）
     *
     * @param data ZIPデータ
     * @param options 画像選択オプション
     * @return 画像データ、見つからない場合はnil
     */
    public static func firstImageData(from data: Data, options: CZFirstImageOptions) -> Data? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageEntries = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        // 1) 表紙らしい名前を優先
        if options.contains(.preferCoverLike) {
            if let best = bestCoverLikeEntry(from: imageEntries) {
                return extractFileData(data: data, entry: best)
            }
        }

        // 2) ゼロパディングされた "1" を優先
        if options.contains(.preferZeroPaddedOne), let cand = imageEntries.first(where: { isZeroPaddedOneFilename($0.filename) }) {
            return extractFileData(data: data, entry: cand)
        }

        // 3) フォールバック：自然順ソートで最小値を取得（ワンパス）
        if let entry = firstImageEntryByNaturalOrderLinear(entries: imageEntries) {
            return extractFileData(data: data, entry: entry)
        }
        return nil
    }

    /**
     * ZIPファイルURLから最初の画像エントリ（ファイル名+データ）を読み込む（オプションフラグ指定）
     *
     * @param url ZIPファイルのURL
     * @param options 画像選択オプション
     * @return 画像エントリ、見つからない場合はnil
     */
    public static func firstImageEntry(from url: URL, options: CZFirstImageOptions) -> CZImageEntry? {
        do { return firstImageEntry(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /**
     * ZIPデータから最初の画像エントリ（ファイル名+データ）を読み込む（オプションフラグ指定）
     *
     * オプションに従って候補エントリを選択（表紙優先 > ゼロパディング "1"）
     *
     * @param data ZIPデータ
     * @param options 画像選択オプション
     * @return 画像エントリ、見つからない場合はnil
     */
    public static func firstImageEntry(from data: Data, options: CZFirstImageOptions) -> CZImageEntry? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let images = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        // オプションに従って候補を選択
        var candidate: CZZipEntry?
        if options.contains(.preferCoverLike) {
            candidate = bestCoverLikeEntry(from: images)
        }
        if candidate == nil, options.contains(.preferZeroPaddedOne) {
            candidate = images.first(where: { isZeroPaddedOneFilename($0.filename) })
        }
        if candidate == nil {
            candidate = firstImageEntryByNaturalOrderLinear(entries: images)
        }
        guard let entry = candidate, let dataOut = extractFileData(data: data, entry: entry) else { return nil }
        return CZImageEntry(filename: entry.filename, imageData: dataOut)
    }

    // MARK: - Streaming thumbnail generation (partial inflate + ImageIO incremental)

    /**
     * ストリーミング展開を使用して最初の画像のサムネイルCGImageを生成する
     *
     * 圧縮時はストリーミング展開を使用し、大きな画像の完全メモリ展開を回避
     * 段階的デコードを試み、サムネイルが生成可能になり次第停止
     *
     * @param url ZIPファイルのURL
     * @param options 画像選択オプション
     * @param maxPixel サムネイルの最大ピクセル長
     * @return サムネイル画像、失敗時はnil
     */
    public static func firstImageThumbnail(from url: URL, options: CZFirstImageOptions, maxPixel: Int) -> CGImage? {
        do { return firstImageThumbnail(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options, maxPixel: maxPixel) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /**
     * ZIPデータから最初の画像のサムネイルCGImageを生成する
     *
     * @param data ZIPデータ
     * @param options 画像選択オプション
     * @param maxPixel サムネイルの最大ピクセル長
     * @return サムネイル画像、失敗時はnil
     */
    public static func firstImageThumbnail(from data: Data, options: CZFirstImageOptions, maxPixel: Int) -> CGImage? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let images = entries.filter { ImageFileFilter.isImagePath($0.filename) }
        guard !images.isEmpty else { return nil }

        // 候補エントリを選択（表紙優先）
        var candidate: CZZipEntry? = nil
        if options.contains(.preferCoverLike) { candidate = bestCoverLikeEntry(from: images) }
        if candidate == nil, options.contains(.preferZeroPaddedOne) {
            candidate = images.first(where: { isZeroPaddedOneFilename($0.filename) })
        }
        if candidate == nil { candidate = firstImageEntryByNaturalOrderLinear(entries: images) }
        guard let entry = candidate else { return nil }

        return createThumbnail(for: entry, in: data, maxPixel: maxPixel)
    }

    // MARK: - Internal helpers for streaming thumbnail

    /**
     * エントリのサムネイルを生成する
     *
     * @param entry ZIPエントリ
     * @param zipData ZIPデータ
     * @param maxPixel サムネイルの最大ピクセル長
     * @return サムネイル画像
     */
    private static func createThumbnail(for entry: CZZipEntry, in zipData: Data, maxPixel: Int) -> CGImage? {
        guard let info = localFileInfo(in: zipData, entry: entry) else { return nil }
        let compMethod = info.method
        let compSlice = zipData.subdata(in: info.fileDataOffset..<(info.fileDataOffset + info.compressedSize))
        if compMethod == 0 {
            return thumbnailFromImageData(compSlice as CFData, maxPixel: maxPixel, isFinal: true)
        }
        if compMethod == 8 {
            return inflateToThumbnail(compressed: compSlice, maxPixel: maxPixel)
        }
        return nil
    }

    /**
     * Local Headerから圧縮方式/ファイルデータオフセット/圧縮サイズを取得する
     *
     * Data Descriptor使用時はその情報を解決する
     *
     * @param data ZIPデータ
     * @param entry ZIPエントリ
     * @return (圧縮方式, ファイルデータオフセット, 圧縮サイズ)
     */
    private static func localFileInfo(in data: Data, entry: CZZipEntry) -> (method: UInt16, fileDataOffset: Int, compressedSize: Int)? {
        let off = entry.localHeaderOffset
        guard off + 30 <= data.count else { return nil }
        // Local Headerシグネチャを検証
        let expected: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
        if !data.subdata(in: off..<(off+4)).elementsEqual(expected) { return nil }
        let fnLen = Int(data.subdata(in: off+26..<(off+28)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let exLen = Int(data.subdata(in: off+28..<(off+30)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let method = data.subdata(in: off+8..<(off+10)).withUnsafeBytes { $0.load(as: UInt16.self) }
        let fileDataOffset = off + 30 + fnLen + exLen
        // Data Descriptor使用時はCentral Directoryのサイズを使用
        let useCompressedSize: Int = (entry.generalPurposeFlag & 0x0008) != 0 ? entry.compressedSize : Int(data.subdata(in: off+18..<(off+22)).withUnsafeBytes { $0.load(as: UInt32.self) })
        guard useCompressedSize > 0, fileDataOffset + useCompressedSize <= data.count else { return nil }
        return (method, fileDataOffset, useCompressedSize)
    }

    /**
     * 画像データからサムネイルを生成する
     *
     * @param imgData 画像データ
     * @param maxPixel サムネイルの最大ピクセル長
     * @param isFinal データが完全かどうか
     * @return サムネイル画像
     */
    private static func thumbnailFromImageData(_ imgData: CFData, maxPixel: Int, isFinal: Bool) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(imgData, nil) else { return nil }
        let opts: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        if let th = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) { return th }
        // 部分データ使用のため段階的ソースを試行
        let inc1 = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(inc1, imgData, isFinal)
        return CGImageSourceCreateThumbnailAtIndex(inc1, 0, opts)
    }

    /**
     * DEFLATE圧縮画像をストリーム展開し、段階的サムネイル生成を試みる
     *
     * @param comp 圧縮データ
     * @param maxPixel サムネイルの最大ピクセル長
     * @return サムネイル画像
     */
    private static func inflateToThumbnail(compressed comp: Data, maxPixel: Int) -> CGImage? {
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        memset(streamPtr, 0, MemoryLayout<compression_stream>.size)
        var status = compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPtr) }

        let dstCap = 64 * 1024
        let dstBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCap)
        defer { dstBuf.deallocate() }

        guard let outData = CFDataCreateMutable(nil, 0) else { return nil }
        let inc = CGImageSourceCreateIncremental(nil)
        let thumbOpts: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        comp.withUnsafeBytes { rawBuf in
            guard let srcBase = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return }
            streamPtr.pointee.src_ptr = srcBase
            streamPtr.pointee.src_size = comp.count
            streamPtr.pointee.dst_ptr = dstBuf
            streamPtr.pointee.dst_size = dstCap

            while status == COMPRESSION_STATUS_OK {
                status = compression_stream_process(streamPtr, Int32(0))
                let written = dstCap - streamPtr.pointee.dst_size
                if written > 0 {
                    CFDataAppendBytes(outData, dstBuf, written)
                    streamPtr.pointee.dst_ptr = dstBuf
                    streamPtr.pointee.dst_size = dstCap
                    // 部分データで段階的ソースを更新（確定せずストリーム継続）
                    CGImageSourceUpdateData(inc, outData, false)
                }

                if status == COMPRESSION_STATUS_END { break }
                if status == COMPRESSION_STATUS_ERROR { break }
                if streamPtr.pointee.src_size == 0 && status == COMPRESSION_STATUS_OK {
                    // 入力がないが終了していない場合、無限ループ回避のため中断
                    break
                }
            }
        }

        // 確定して完全データからサムネイルを構築
        CGImageSourceUpdateData(inc, outData, true)
        if let th = CGImageSourceCreateThumbnailAtIndex(inc, 0, thumbOpts) { return th }
        // 最終フォールバック：フル画像を作成（重い可能性あり）
        return CGImageSourceCreateImageAtIndex(inc, 0, nil)
    }

    /**
     * ZIPデータから最初の画像データを読み込む（早期選択ルール付き）
     *
     * @param data ZIPデータ
     * @param isZeroPaddedFirstPreferred trueの場合、ゼロパディングされた "1" を優先
     * @return 画像データ、見つからない場合はnil
     */
    public static func firstImageData(from data: Data, isZeroPaddedFirstPreferred: Bool) -> Data? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageEntries = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        if isZeroPaddedFirstPreferred, let candidate = imageEntries.first(where: { isZeroPaddedOneFilename($0.filename) }) {
            return extractFileData(data: data, entry: candidate)
        }

        // フォールバック：自然順ソートで最初のエントリを決定し、そのファイルのみを抽出
        if let entry = firstImageEntryByNaturalOrderLinear(entries: imageEntries) {
            return extractFileData(data: data, entry: entry)
        }
        return nil
    }

    // MARK: - Low-level ZIP helpers

    /**
     * Central Directoryのオフセットを検索する
     *
     * ZIPファイルの末尾からEnd of Central Directory Record（EOCDR）を逆引き検索
     * EOCDRにはCentral Directoryの位置情報が含まれる
     *
     * 検索範囲：最後の65536バイト（ZIPコメントの最大長を考慮）
     * シグネチャ：0x06054b50（EOCDR）
     *
     * @param data ZIPデータ
     * @return Central Directoryのオフセット、見つからない場合はnil
     */
    private static func findCentralDirectoryOffset(in data: Data) -> Int? {
        // EOCDR signature 0x06054b50
        let sig: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let searchStart = max(0, data.count - 65536)
        if data.count < 22 { return nil }
        var i = data.count - 4
        while i >= searchStart {
            if data.subdata(in: i..<(i+4)).elementsEqual(sig) {
                if i + 20 <= data.count {
                    let offsetBytes = data.subdata(in: i+16..<(i+20))
                    let offset = offsetBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
                    return Int(offset)
                }
                break
            }
            i -= 1
        }
        return nil
    }

    /**
     * Central Directoryを解析してエントリ一覧を取得する
     *
     * Central Directoryには、ZIP内の全ファイルのメタデータが格納されている
     * 各エントリから以下の情報を抽出：
     * - ファイル名
     * - Local Headerのオフセット（実データの位置）
     * - 圧縮サイズ
     * - General Purpose Flag（Data Descriptor使用判定等）
     * - 圧縮方式（0=非圧縮、8=DEFLATE）
     *
     * @param data ZIPデータ
     * @param offset Central Directoryの開始オフセット
     * @return ZIPエントリの配列
     */
    private static func parseCentralDirectory(data: Data, offset: Int) -> [CZZipEntry] {
        var entries: [CZZipEntry] = []
        var cur = offset
        let expected: [UInt8] = [0x50, 0x4b, 0x01, 0x02] // Central Directory File Header signature
        while cur + 46 <= data.count {
            let sig = data.subdata(in: cur..<(cur+4))
            if !sig.elementsEqual(expected) { break }

            let gpFlag = data.subdata(in: cur+8..<(cur+10)).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compMethod = data.subdata(in: cur+10..<(cur+12)).withUnsafeBytes { $0.load(as: UInt16.self) }
            let cdCompressed = data.subdata(in: cur+20..<(cur+24)).withUnsafeBytes { $0.load(as: UInt32.self) }
            let fnLen = Int(data.subdata(in: cur+28..<(cur+30)).withUnsafeBytes { $0.load(as: UInt16.self) })
            let exLen = Int(data.subdata(in: cur+30..<(cur+32)).withUnsafeBytes { $0.load(as: UInt16.self) })
            let cmLen = Int(data.subdata(in: cur+32..<(cur+34)).withUnsafeBytes { $0.load(as: UInt16.self) })
            let nameStart = cur + 46
            let nameEnd = nameStart + fnLen
            if nameEnd > data.count { break }
            let filenameData = data.subdata(in: nameStart..<nameEnd)
            let filename = String(data: filenameData, encoding: .utf8) ?? ""
            let localHeaderOffset = data.subdata(in: cur+42..<(cur+46)).withUnsafeBytes { $0.load(as: UInt32.self) }

            entries.append(CZZipEntry(
                filename: filename,
                localHeaderOffset: Int(localHeaderOffset),
                compressedSize: Int(cdCompressed),
                generalPurposeFlag: gpFlag,
                compressionMethod: compMethod
            ))

            cur = nameEnd + exLen + cmLen
        }
        return entries
    }

    /**
     * ZIPエントリからファイルデータを抽出する
     *
     * 処理フロー：
     * 1. Local File Headerを検証
     * 2. ファイルデータの位置とサイズを計算
     * 3. Data Descriptor使用時はCentral Directoryのサイズを使用
     * 4. 圧縮方式に応じて処理：
     *    - 方式0（非圧縮）：そのまま返す
     *    - 方式8（DEFLATE）：展開して返す
     *
     * @param data ZIPデータ
     * @param entry ZIPエントリ（Central Directoryから取得）
     * @return 展開されたファイルデータ、失敗時はnil
     */
    private static func extractFileData(data: Data, entry: CZZipEntry) -> Data? {
        let off = entry.localHeaderOffset
        guard off + 30 <= data.count else { return nil }
        let expected: [UInt8] = [0x50, 0x4b, 0x03, 0x04] // Local File Header signature
        let sig = data.subdata(in: off..<(off+4))
        if !sig.elementsEqual(expected) { return nil }

        let fnLen = Int(data.subdata(in: off+26..<(off+28)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let exLen = Int(data.subdata(in: off+28..<(off+30)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let lhCompressed = data.subdata(in: off+18..<(off+22)).withUnsafeBytes { $0.load(as: UInt32.self) }
        let method = data.subdata(in: off+8..<(off+10)).withUnsafeBytes { $0.load(as: UInt16.self) }

        let fileDataOffset = off + 30 + fnLen + exLen
        // Data Descriptor使用時（bit 3が立っている）はCentral Directoryのサイズを使用
        let useCompressedSize: Int = (entry.generalPurposeFlag & 0x0008) != 0 ? entry.compressedSize : Int(lhCompressed)
        guard useCompressedSize > 0, fileDataOffset + useCompressedSize <= data.count else { return nil }
        let fileData = data.subdata(in: fileDataOffset..<(fileDataOffset + useCompressedSize))

        if method == 0 { return fileData } // 非圧縮
        if method == 8 { return inflateData(fileData) } // DEFLATE展開
        return nil // 未対応の圧縮方式
    }

    /**
     * DEFLATE圧縮データを展開する
     *
     * Foundation/Compressionを使用してZLIB（DEFLATE）形式のデータを展開
     *
     * 処理方式：
     * - 8MBバッファによるストリーム展開（メモリ効率を考慮）
     * - 展開サイズの上限チェック（異常データ対策）
     *
     * @param compressedData 圧縮されたデータ
     * @return 展開されたデータ、失敗時はnil
     */
    private static func inflateData(_ compressedData: Data) -> Data? {
        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }
        memset(streamPtr, 0, MemoryLayout<compression_stream>.size)

        var status = compression_stream_init(streamPtr, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPtr) }

        let chunkSize = 64 * 1024
        let chunkBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { chunkBuffer.deallocate() }

        guard let outputData = CFDataCreateMutable(nil, 0) else { return nil }

        let finalizeFlag = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
        var flags: Int32 = 0
        var didRequestFinal = false

        return compressedData.withUnsafeBytes { rawBuf -> Data? in
            guard let srcBase = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return nil }

            streamPtr.pointee.src_ptr = srcBase
            streamPtr.pointee.src_size = compressedData.count
            streamPtr.pointee.dst_ptr = chunkBuffer
            streamPtr.pointee.dst_size = chunkSize

            while true {
                let previousSrcSize = streamPtr.pointee.src_size
                status = compression_stream_process(streamPtr, flags)

                let produced = chunkSize - streamPtr.pointee.dst_size
                if produced > 0 {
                    CFDataAppendBytes(outputData, chunkBuffer, produced)
                    streamPtr.pointee.dst_ptr = chunkBuffer
                    streamPtr.pointee.dst_size = chunkSize
                }

                switch status {
                case COMPRESSION_STATUS_OK:
                    if streamPtr.pointee.src_size == 0 && !didRequestFinal {
                        flags = finalizeFlag
                        didRequestFinal = true
                    } else if streamPtr.pointee.src_size == 0 && didRequestFinal && previousSrcSize == 0 && produced == 0 {
                        return nil
                    }
                case COMPRESSION_STATUS_END:
                    return Data(referencing: outputData)
                case COMPRESSION_STATUS_ERROR:
                    return nil
                default:
                    return nil
                }
            }
        }
    }

    /**
     * lastPathComponentに対する自然順ソートで最初の画像エントリを返す
     *
     * ソート済み配列を割り当てずに線形検索で最小値を取得
     *
     * @param entries ZIPエントリの配列
     * @return 自然順で最小のエントリ
     */
    private static func firstImageEntryByNaturalOrderLinear(entries: [CZZipEntry]) -> CZZipEntry? {
        guard var best = entries.first else { return nil }
        for e in entries.dropFirst() {
            if NaturalSort.lessFilename((e.filename as NSString).lastPathComponent,
                                        (best.filename as NSString).lastPathComponent) {
                best = e
            }
        }
        return best
    }

    /// Detects filenames like "01.jpg", "001.png", "0001.tif", and also variants such as
    /// "image001.jpg" as early-first candidates.
    /// The rule checks the basename (without extension) and returns true when it contains
    /// a token matching one or more zeros followed by a single '1', and that token is bounded
    /// by non-digits or string boundaries.
    /// Examples: "01", "001", "001-cover", "image001" => true; "1", "011", "0012" => false
    private static func isZeroPaddedOneFilename(_ path: String) -> Bool {
        let last = (path as NSString).lastPathComponent
        let base = (last as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        // Regex: (?:^|\D)0+1(?:\D|$)
        // At least one leading zero before '1'; non-digit or end must follow the '1'.
        // Also requires a non-digit or start before the zeros to avoid being inside a longer number.
        do {
            let re = try NSRegularExpression(pattern: "(?:^|\\D)0+1(?:\\D|$)", options: [])
            let range = NSRange(location: 0, length: (base as NSString).length)
            return re.firstMatch(in: base, options: [], range: range) != nil
        } catch {
            // Fallback: simple check without regex
            if base.contains("001") || base.contains("01") { return true }
            return false
        }
    }

    // MARK: - Cover-like scoring

    /**
     * 最も表紙らしいエントリを簡易スコアヒューリスティックで選択する
     *
     * 複数のエントリが同点の場合は、自然順で最小のものを選択
     *
     * @param entries ZIPエントリの配列
     * @return 最も表紙らしいエントリ
     */
    private static func bestCoverLikeEntry(from entries: [CZZipEntry]) -> CZZipEntry? {
        var best: CZZipEntry? = nil
        var bestScore = 0
        for e in entries {
            let s = coverLikeScore(for: e.filename)
            if s > 0 {
                if best == nil || s > bestScore || (s == bestScore && NaturalSort.lessFilename((e.filename as NSString).lastPathComponent,
                                                                                               (best!.filename as NSString).lastPathComponent)) {
                    best = e
                    bestScore = s
                }
            }
        }
        return best
    }

    /// Score filenames that look like a cover: contains keywords like "cover", "front", "表紙",
    /// or basename equals/starts with multiple zeros (e.g. "00", "000", "0000", "000-cover").
    /// Stronger hints yield higher scores.
    private static func coverLikeScore(for path: String) -> Int {
        let last = (path as NSString).lastPathComponent
        let base = (last as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = base.lowercased()
        var score = 0

        // Strong keywords
        if lower.contains("cover") { score += 100 }
        if lower.contains("front") { score += 80 }
        if base.contains("表紙") { score += 100 }

        // Leading zeros like 00, 000, 0000 (but not a longer number like 0012 which is page 12)
        do {
            // (?:^|\D)0{2,}(?:\D|$) : 2+ zeros at token boundary, followed by non-digit or end
            // This matches "000", "image_000", "p-000" but not "0001" or "page0001"
            let re = try NSRegularExpression(pattern: "(?:^|\\D)0{2,}(?:\\D|$)", options: [])
            let range = NSRange(location: 0, length: (base as NSString).length)
            if re.firstMatch(in: base, options: [], range: range) != nil { score += 60 }
        } catch {
            if lower.hasPrefix("00") || lower.contains("_00") || lower.contains("-00") { score += 60 }
        }

        // Reuse zero-padded "1" hint as a weaker cover signal (many archives label 001 as cover)
        if isZeroPaddedOneFilename(path) { score += 50 }

        return score
    }
}

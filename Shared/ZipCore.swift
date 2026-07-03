//
//  ZipCore.swift
//  CoverZip で共有する ZIP 解析・展開ユーティリティ
//

import Foundation
import Compression
import ImageIO
import Darwin

public struct CZZipEntry {
    public let filename: String
    public let localHeaderOffset: Int
    public let compressedSize: Int
    public let uncompressedSize: Int
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

public enum CZZip {
    public typealias FirstImageThumbnailResult = CZFirstImageThumbnailResult

    /// ファイル名（lastPathComponent）の自然順でエントリをソートする。
    /// 比較のたびに再トークン化しないよう、ソートキーを事前計算するSchwartzian transform。
    private static func sortedByNaturalFilename(_ entries: [CZZipEntry]) -> [CZZipEntry] {
        return entries
            .map { ($0, NaturalSort.NaturalSortKey(($0.filename as NSString).lastPathComponent)) }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    /// ZIP データから全画像エントリを読み込む（ファイル名の自然順ソート）。
    public static func imageEntries(from data: Data) -> [CZImageEntry] {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return [] }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageFiles = sortedByNaturalFilename(entries.filter { ImageFileFilter.isImagePath($0.filename) })
        var result: [CZImageEntry] = []
        result.reserveCapacity(imageFiles.count)
        for entry in imageFiles {
            if let img = extractFileData(data: data, entry: entry) {
                result.append(CZImageEntry(filename: entry.filename, imageData: img))
            }
        }
        return result
    }

    /// ZIP ファイル URL から全画像エントリを読み込む。
    public static func imageEntries(from url: URL) -> [CZImageEntry] {
        do { return imageEntries(from: try Data(contentsOf: url, options: [.mappedIfSafe])) }
        catch { NSLog("CZZip read error: \(error)"); return [] }
    }

    /// ZIP データから画像エントリのメタデータだけを読み込む（画像データは未読込）。
    /// 遅延ロード向けに全画像を高速列挙できる。
    public static func imageEntryInfoList(from data: Data) -> [CZImageEntryInfo] {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return [] }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageFiles = sortedByNaturalFilename(entries.filter { ImageFileFilter.isImagePath($0.filename) })
        return imageFiles.map { CZImageEntryInfo(filename: $0.filename, entry: $0) }
    }

    /// ZIP ファイル URL から画像エントリのメタデータを読み込む。
    public static func imageEntryInfoList(from url: URL) -> [CZImageEntryInfo] {
        do { return imageEntryInfoList(from: try Data(contentsOf: url, options: [.mappedIfSafe])) }
        catch { NSLog("CZZip read error: \(error)"); return [] }
    }

    /// ZIP データから指定エントリ情報の画像データを抽出する。
    public static func extractImageData(from zipData: Data, entryInfo: CZImageEntryInfo) -> Data? {
        return extractFileData(data: zipData, entry: entryInfo.entry)
    }

    /// ZIP ファイル URL から先頭画像データ（自然順基準）を読み込む。
    public static func firstImageData(from url: URL) -> Data? {
        return imageEntries(from: url).first?.imageData
    }

    /// 早期選択ルール付きで先頭画像データを読み込む。
    /// - Parameters:
    ///   - url: ZIP ファイル URL
    ///   - isZeroPaddedFirstPreferred: true の場合、ベース名にゼロ埋めの "1" トークン
    ///     （例: 01, 001, ...）を含むファイルを優先する。
    ///     先頭一致でなくても対象（例: "image001"）。見つかればソートせず早期確定し、
    ///     見つからなければ自然順先頭へフォールバックする。
    /// - Returns: 見つかった画像データ。存在しない場合は nil。
    public static func firstImageData(from url: URL, isZeroPaddedFirstPreferred: Bool) -> Data? {
        do { return firstImageData(from: try Data(contentsOf: url, options: [.mappedIfSafe]), isZeroPaddedFirstPreferred: isZeroPaddedFirstPreferred) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /// オプションフラグ（ヒューリスティック + 自然順フォールバック）で先頭画像データを読み込む。
    public static func firstImageData(from url: URL, options: CZFirstImageOptions) -> Data? {
        do { return firstImageData(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /// 生 ZIP データからオプションフラグで先頭画像データを読み込む。
    public static func firstImageData(from data: Data, options: CZFirstImageOptions) -> Data? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageEntries = entries.filter { ImageFileFilter.isImagePath($0.filename) }
        guard let index = CZCoverSelector.selectIndex(filenames: imageEntries.map(\.filename), options: options) else { return nil }
        return extractFileData(data: data, entry: imageEntries[index])
    }

    /// オプションフラグで先頭画像エントリ（ファイル名 + データ）を読み込む。
    public static func firstImageEntry(from url: URL, options: CZFirstImageOptions) -> CZImageEntry? {
        do { return firstImageEntry(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /// 生データからオプションフラグで先頭画像エントリ（ファイル名 + データ）を読み込む。
    public static func firstImageEntry(from data: Data, options: CZFirstImageOptions) -> CZImageEntry? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let images = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        guard let index = CZCoverSelector.selectIndex(filenames: images.map(\.filename), options: options),
              let dataOut = extractFileData(data: data, entry: images[index]) else { return nil }
        let entry = images[index]
        return CZImageEntry(filename: entry.filename, imageData: dataOut)
    }

    // MARK: - ストリーミングサムネイル生成（部分展開 + ImageIO インクリメンタル）

    /// 圧縮時はストリーミング展開を使って先頭画像のサムネイル CGImage を生成する。
    /// 大きな画像でも全展開を避けるため、段階的デコードを試み、サムネイル取得時点で処理を打ち切る。
    public static func firstImageThumbnail(from url: URL, options: CZFirstImageOptions, maxPixel: Int) -> FirstImageThumbnailResult {
        do { return firstImageThumbnail(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options, maxPixel: maxPixel) }
        catch { NSLog("CZZip read error: \(error)"); return .none }
    }

    public static func firstImageThumbnail(from data: Data, options: CZFirstImageOptions, maxPixel: Int) -> FirstImageThumbnailResult {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return .none }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let images = entries.filter { ImageFileFilter.isImagePath($0.filename) }
        guard !images.isEmpty else { return .none }

        guard let index = CZCoverSelector.selectIndex(filenames: images.map(\.filename), options: options) else { return .none }
        let entry = images[index]

        if let cgImage = createThumbnail(for: entry, in: data, maxPixel: maxPixel) {
            return .thumbnail(cgImage)
        }
        // サムネイル生成に失敗した場合は、同じエントリの展開済みデータをそのまま返す
        if let raw = extractFileData(data: data, entry: entry) {
            return .rawData(raw)
        }
        return .none
    }

    // MARK: - ストリーミングサムネイル内部ヘルパー
    private static func createThumbnail(for entry: CZZipEntry, in zipData: Data, maxPixel: Int) -> CGImage? {
        guard let info = localFileInfo(in: zipData, entry: entry) else { return nil }
        return zipData.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> CGImage? in
            let payload = UnsafeRawBufferPointer(rebasing: buf[info.fileDataOffset..<(info.fileDataOffset + info.compressedSize)])
            if info.method == 0 {
                let compData = Data(bytes: payload.baseAddress!, count: payload.count)
                return CZCoverSelector.thumbnail(fromImageData: compData, maxPixel: maxPixel)
            }
            if info.method == 8 {
                let decompressed = inflateDataOneShot(payload, expectedSize: entry.uncompressedSize)
                    ?? inflateData(Data(bytes: payload.baseAddress!, count: payload.count))
                guard let decompressed else { return nil }
                return CZCoverSelector.thumbnail(fromImageData: decompressed, maxPixel: maxPixel)
            }
            return nil
        }
    }

    /// ローカルヘッダから method / fileDataOffset / compressedSize を取得する（必要時は data descriptor を解決）。
    private static func localFileInfo(in data: Data, entry: CZZipEntry) -> (method: UInt16, fileDataOffset: Int, compressedSize: Int)? {
        let off = entry.localHeaderOffset
        guard off + 30 <= data.count else { return nil }
        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> (method: UInt16, fileDataOffset: Int, compressedSize: Int)? in
            // ローカルヘッダ署名を検証
            guard matchesPKSignature(buf, off, 0x03, 0x04) else { return nil }
            let fnLen = Int(readLE16(buf, off + 26))
            let exLen = Int(readLE16(buf, off + 28))
            let method = readLE16(buf, off + 8)
            let fileDataOffset = off + 30 + fnLen + exLen
            // data descriptor 使用時は Central Directory 側のサイズを採用
            let useCompressedSize: Int = (entry.generalPurposeFlag & 0x0008) != 0 ? entry.compressedSize : Int(readLE32(buf, off + 18))
            guard useCompressedSize > 0, fileDataOffset + useCompressedSize <= buf.count else { return nil }
            return (method, fileDataOffset, useCompressedSize)
        }
    }

    /// 生 ZIP データから早期選択ルール付きで先頭画像データを読み込む。
    public static func firstImageData(from data: Data, isZeroPaddedFirstPreferred: Bool) -> Data? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageEntries = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        let options: CZFirstImageOptions = isZeroPaddedFirstPreferred ? [.preferZeroPaddedOne] : []
        guard let index = CZCoverSelector.selectIndex(filenames: imageEntries.map(\.filename), options: options) else { return nil }
        return extractFileData(data: data, entry: imageEntries[index])
    }

    // MARK: - 低レベル ZIP ヘルパー

    /// `buf[offset..<offset+2]` をリトルエンディアンの UInt16 として読む。
    /// 呼び出し側で `offset + 2 <= buf.count` を保証すること。
    @inline(__always)
    private static func readLE16(_ buf: UnsafeRawBufferPointer, _ offset: Int) -> UInt16 {
        let b0 = UInt16(buf[offset])
        let b1 = UInt16(buf[offset + 1])
        return b0 | (b1 << 8)
    }

    /// `buf[offset..<offset+4]` をリトルエンディアンの UInt32 として読む。
    /// 呼び出し側で `offset + 4 <= buf.count` を保証すること。
    @inline(__always)
    private static func readLE32(_ buf: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        let b0 = UInt32(buf[offset])
        let b1 = UInt32(buf[offset + 1])
        let b2 = UInt32(buf[offset + 2])
        let b3 = UInt32(buf[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    /// `buf[offset..<offset+4]` が ZIP の "PK" 系署名 `50 4b b2 b3` と一致するかを判定する。
    /// 呼び出し側で `offset + 4 <= buf.count` を保証すること。
    @inline(__always)
    private static func matchesPKSignature(_ buf: UnsafeRawBufferPointer, _ offset: Int, _ b2: UInt8, _ b3: UInt8) -> Bool {
        return buf[offset] == 0x50 && buf[offset + 1] == 0x4b && buf[offset + 2] == b2 && buf[offset + 3] == b3
    }

    private static func findCentralDirectoryOffset(in data: Data) -> Int? {
        if data.count < 22 { return nil }
        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Int? in
            // EOCDR 署名 0x06054b50 を末尾から後方走査
            let searchStart = max(0, buf.count - 65536)
            var i = buf.count - 4
            while i >= searchStart {
                if matchesPKSignature(buf, i, 0x05, 0x06) {
                    if i + 20 <= buf.count {
                        return Int(readLE32(buf, i + 16))
                    }
                    break
                }
                i -= 1
            }
            return nil
        }
    }

    private static func parseCentralDirectory(data: Data, offset: Int) -> [CZZipEntry] {
        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> [CZZipEntry] in
            var entries: [CZZipEntry] = []
            var cur = offset
            while cur + 46 <= buf.count {
                if !matchesPKSignature(buf, cur, 0x01, 0x02) { break }

                let gpFlag = readLE16(buf, cur + 8)
                let compMethod = readLE16(buf, cur + 10)
                let cdCompressed = readLE32(buf, cur + 20)
                let cdUncompressed = readLE32(buf, cur + 24)
                let fnLen = Int(readLE16(buf, cur + 28))
                let exLen = Int(readLE16(buf, cur + 30))
                let cmLen = Int(readLE16(buf, cur + 32))
                let nameStart = cur + 46
                let nameEnd = nameStart + fnLen
                if nameEnd > buf.count { break }
                let filename = String(data: Data(buf[nameStart..<nameEnd]), encoding: .utf8) ?? ""
                let localHeaderOffset = readLE32(buf, cur + 42)

                entries.append(CZZipEntry(
                    filename: filename,
                    localHeaderOffset: Int(localHeaderOffset),
                    compressedSize: Int(cdCompressed),
                    uncompressedSize: Int(cdUncompressed),
                    generalPurposeFlag: gpFlag,
                    compressionMethod: compMethod
                ))

                cur = nameEnd + exLen + cmLen
            }
            return entries
        }
    }

    private static func extractFileData(data: Data, entry: CZZipEntry) -> Data? {
        let off = entry.localHeaderOffset
        guard off + 30 <= data.count else { return nil }

        return data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Data? in
            guard matchesPKSignature(buf, off, 0x03, 0x04) else { return nil }

            let fnLen = Int(readLE16(buf, off + 26))
            let exLen = Int(readLE16(buf, off + 28))
            let lhCompressed = readLE32(buf, off + 18)
            let method = readLE16(buf, off + 8)

            let fileDataOffset = off + 30 + fnLen + exLen
            let useCompressedSize: Int = (entry.generalPurposeFlag & 0x0008) != 0 ? entry.compressedSize : Int(lhCompressed)
            guard useCompressedSize > 0, fileDataOffset + useCompressedSize <= buf.count else { return nil }
            let payload = UnsafeRawBufferPointer(rebasing: buf[fileDataOffset..<(fileDataOffset + useCompressedSize)])

            if method == 0 {
                return Data(bytes: payload.baseAddress!, count: payload.count)
            }
            if method == 8 {
                if let oneShot = inflateDataOneShot(payload, expectedSize: entry.uncompressedSize) {
                    return oneShot
                }
                // 一発展開不可（サイズ未知/不一致）の場合のみ、コピーしてストリーミング展開へフォールバック
                return inflateData(Data(bytes: payload.baseAddress!, count: payload.count))
            }
            return nil
        }
    }

    /// Central Directory のuncompressedSizeを使い、出力バッファを一発確保してDEFLATE展開する。
    /// `expectedSize` が 0 または上限超過、もしくは展開結果サイズが一致しない場合は nil を返し、
    /// 呼び出し側はストリーミング実装(`inflateData`)へフォールバックする。
    private static let maxOneShotInflateSize = 256 * 1024 * 1024

    private static func inflateDataOneShot(_ src: UnsafeRawBufferPointer, expectedSize: Int) -> Data? {
        guard expectedSize > 0, expectedSize <= maxOneShotInflateSize,
              let srcBase = src.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }

        var dst = Data(count: expectedSize)
        let written: Int = dst.withUnsafeMutableBytes { (dstBuf: UnsafeMutableRawBufferPointer) in
            guard let dstBase = dstBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(dstBase, expectedSize, srcBase, src.count, nil, COMPRESSION_ZLIB)
        }
        guard written == expectedSize else { return nil }
        return dst
    }

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

}

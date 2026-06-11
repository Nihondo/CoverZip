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

/// ZIP から先頭画像を選ぶ際の方針オプション。
public struct CZFirstImageOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// ゼロ埋めの「1」トークン（例: 01, 001, image001）を含む名前を優先し、見つけた時点で早期確定する。
    public static let preferZeroPaddedOne = CZFirstImageOptions(rawValue: 1 << 0)
    /// 表紙らしい名前（例: "cover" / "front" / "表紙" / 先頭 00・000・0000）を優先する。
    public static let preferCoverLike = CZFirstImageOptions(rawValue: 1 << 1)
}

public enum CZZip {
    /// ZIP データから全画像エントリを読み込む（ファイル名の自然順ソート）。
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
        let imageFiles = entries
            .filter { ImageFileFilter.isImagePath($0.filename) }
            .sorted { a, b in
                NaturalSort.lessFilename((a.filename as NSString).lastPathComponent,
                                          (b.filename as NSString).lastPathComponent)
            }
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

        // 1) まず表紙らしい名前を優先（例: "cover" / "front" / "表紙" / 先頭 00・000・0000）
        if options.contains(.preferCoverLike) {
            if let best = bestCoverLikeEntry(from: imageEntries) {
                return extractFileData(data: data, entry: best)
            }
        }

        // 2) 次にゼロ埋め "1" を優先（例: 01, 001, image001）
        if options.contains(.preferZeroPaddedOne), let cand = imageEntries.first(where: { isZeroPaddedOneFilename($0.filename) }) {
            return extractFileData(data: data, entry: cand)
        }

        // 3) フォールバック: NaturalSort による 1 パス最小値探索（全体ソートなし）
        if let entry = firstImageEntryByNaturalOrderLinear(entries: imageEntries) {
            return extractFileData(data: data, entry: entry)
        }
        return nil
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

        // オプションに応じて候補エントリを選択（表紙らしさ > ゼロ埋め "1" の順）
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

    // MARK: - ストリーミングサムネイル生成（部分展開 + ImageIO インクリメンタル）

    /// 圧縮時はストリーミング展開を使って先頭画像のサムネイル CGImage を生成する。
    /// 大きな画像でも全展開を避けるため、段階的デコードを試み、サムネイル取得時点で処理を打ち切る。
    public static func firstImageThumbnail(from url: URL, options: CZFirstImageOptions, maxPixel: Int) -> CGImage? {
        do { return firstImageThumbnail(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options, maxPixel: maxPixel) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    public static func firstImageThumbnail(from data: Data, options: CZFirstImageOptions, maxPixel: Int) -> CGImage? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let images = entries.filter { ImageFileFilter.isImagePath($0.filename) }
        guard !images.isEmpty else { return nil }

        // 候補エントリを選択（表紙らしさ優先）
        var candidate: CZZipEntry? = nil
        if options.contains(.preferCoverLike) { candidate = bestCoverLikeEntry(from: images) }
        if candidate == nil, options.contains(.preferZeroPaddedOne) {
            candidate = images.first(where: { isZeroPaddedOneFilename($0.filename) })
        }
        if candidate == nil { candidate = firstImageEntryByNaturalOrderLinear(entries: images) }
        guard let entry = candidate else { return nil }

        return createThumbnail(for: entry, in: data, maxPixel: maxPixel)
    }

    // MARK: - ストリーミングサムネイル内部ヘルパー
    private static func createThumbnail(for entry: CZZipEntry, in zipData: Data, maxPixel: Int) -> CGImage? {
        guard let info = localFileInfo(in: zipData, entry: entry) else { return nil }
        let compMethod = info.method
        let compSlice = zipData.subdata(in: info.fileDataOffset..<(info.fileDataOffset + info.compressedSize))
        if compMethod == 0 {
            return thumbnailFromImageData(compSlice as CFData, maxPixel: maxPixel, isFinal: true)
        }
        if compMethod == 8 {
            guard let decompressed = inflateData(compSlice) else { return nil }
            return thumbnailFromImageData(decompressed as CFData, maxPixel: maxPixel, isFinal: true)
        }
        return nil
    }

    /// ローカルヘッダから method / fileDataOffset / compressedSize を取得する（必要時は data descriptor を解決）。
    private static func localFileInfo(in data: Data, entry: CZZipEntry) -> (method: UInt16, fileDataOffset: Int, compressedSize: Int)? {
        let off = entry.localHeaderOffset
        guard off + 30 <= data.count else { return nil }
        // ローカルヘッダ署名を検証
        let expected: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
        if !data.subdata(in: off..<(off+4)).elementsEqual(expected) { return nil }
        let fnLen = Int(data.subdata(in: off+26..<(off+28)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let exLen = Int(data.subdata(in: off+28..<(off+30)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let method = data.subdata(in: off+8..<(off+10)).withUnsafeBytes { $0.load(as: UInt16.self) }
        let fileDataOffset = off + 30 + fnLen + exLen
        // data descriptor 使用時は Central Directory 側のサイズを採用
        let useCompressedSize: Int = (entry.generalPurposeFlag & 0x0008) != 0 ? entry.compressedSize : Int(data.subdata(in: off+18..<(off+22)).withUnsafeBytes { $0.load(as: UInt32.self) })
        guard useCompressedSize > 0, fileDataOffset + useCompressedSize <= data.count else { return nil }
        return (method, fileDataOffset, useCompressedSize)
    }

    private static func thumbnailFromImageData(_ imgData: CFData, maxPixel: Int, isFinal: Bool) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(imgData, nil) else { return nil }
        let opts: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        if let th = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) { return th }
        // 部分データ利用のためインクリメンタルソースも試す
        let inc1 = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(inc1, imgData, isFinal)
        return CGImageSourceCreateThumbnailAtIndex(inc1, 0, opts)
    }

    /// 生 ZIP データから早期選択ルール付きで先頭画像データを読み込む。
    public static func firstImageData(from data: Data, isZeroPaddedFirstPreferred: Bool) -> Data? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageEntries = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        if isZeroPaddedFirstPreferred, let candidate = imageEntries.first(where: { isZeroPaddedOneFilename($0.filename) }) {
            return extractFileData(data: data, entry: candidate)
        }

        // フォールバック: ファイル名だけ自然順で先頭を決め、その1件だけ展開する。
        if let entry = firstImageEntryByNaturalOrderLinear(entries: imageEntries) {
            return extractFileData(data: data, entry: entry)
        }
        return nil
    }

    // MARK: - 低レベル ZIP ヘルパー

    private static func findCentralDirectoryOffset(in data: Data) -> Int? {
        // EOCDR 署名 0x06054b50
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

    private static func parseCentralDirectory(data: Data, offset: Int) -> [CZZipEntry] {
        var entries: [CZZipEntry] = []
        var cur = offset
        let expected: [UInt8] = [0x50, 0x4b, 0x01, 0x02]
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

    private static func extractFileData(data: Data, entry: CZZipEntry) -> Data? {
        let off = entry.localHeaderOffset
        guard off + 30 <= data.count else { return nil }
        let expected: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
        let sig = data.subdata(in: off..<(off+4))
        if !sig.elementsEqual(expected) { return nil }

        let fnLen = Int(data.subdata(in: off+26..<(off+28)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let exLen = Int(data.subdata(in: off+28..<(off+30)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let lhCompressed = data.subdata(in: off+18..<(off+22)).withUnsafeBytes { $0.load(as: UInt32.self) }
        let method = data.subdata(in: off+8..<(off+10)).withUnsafeBytes { $0.load(as: UInt16.self) }

        let fileDataOffset = off + 30 + fnLen + exLen
        let useCompressedSize: Int = (entry.generalPurposeFlag & 0x0008) != 0 ? entry.compressedSize : Int(lhCompressed)
        guard useCompressedSize > 0, fileDataOffset + useCompressedSize <= data.count else { return nil }
        let fileData = data.subdata(in: fileDataOffset..<(fileDataOffset + useCompressedSize))

        if method == 0 { return fileData }
        if method == 8 { return inflateData(fileData) }
        return nil
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

    /// lastPathComponent を NaturalSort で比較し、ソート配列を作らずに先頭エントリを返す。
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

    /// "01" の前に 0 が1つ以上あるかを判定する正規表現（呼び出しごとの再コンパイルを避けるため静的に保持）。
    private static let zeroPaddedOneRegex = try? NSRegularExpression(pattern: "(?:^|\\D)0+1(?:\\D|$)")
    /// 先頭ゼロ群（00/000/0000 など）を検出する正規表現（呼び出しごとの再コンパイルを避けるため静的に保持）。
    private static let leadingZerosRegex = try? NSRegularExpression(pattern: "(?:^|\\D)0{2,}(?:\\D|$)")

    /// "01.jpg" / "001.png" / "0001.tif" や "image001.jpg" のような
    /// 「先頭候補」ファイル名を検出する。
    /// 拡張子を除いたベース名に対し、
    /// 「1つ以上の 0 の後ろに単独の 1」があり、前後が非数字または文字列境界で区切られる場合に true。
    /// 例: "01" / "001" / "001-cover" / "image001" は true、"1" / "011" / "0012" は false。
    private static func isZeroPaddedOneFilename(_ path: String) -> Bool {
        let last = (path as NSString).lastPathComponent
        let base = (last as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        // 正規表現: (?:^|\D)0+1(?:\D|$)
        // "1" の前に 0 が1つ以上あり、かつ "1" の後ろが非数字または末尾であること。
        // さらに、0 群の前も非数字または先頭に限定し、長い数字列の途中一致を避ける。
        guard let re = zeroPaddedOneRegex else {
            // フォールバック: 正規表現が使えない場合の簡易判定
            return base.contains("001") || base.contains("01")
        }
        let range = NSRange(location: 0, length: (base as NSString).length)
        return re.firstMatch(in: base, options: [], range: range) != nil
    }

    // MARK: - 表紙らしさスコア
    /// 単純なスコアリングで最も表紙らしいエントリを選ぶ。
    /// 同点の場合は自然順で最小のものを採用する。
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

    /// 表紙らしいファイル名にスコアを付ける。
    /// 例: "cover" / "front" / "表紙" を含む、
    /// またはベース名が複数ゼロ（例: "00", "000", "0000", "000-cover"）を持つ場合に加点。
    /// 手掛かりが強いほど高得点になる。
    private static func coverLikeScore(for path: String) -> Int {
        let last = (path as NSString).lastPathComponent
        let base = (last as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = base.lowercased()
        var score = 0

        // 強いキーワード
        if lower.contains("cover") { score += 100 }
        if lower.contains("front") { score += 80 }
        if base.contains("表紙") { score += 100 }

        // 先頭ゼロ群（00/000/0000 など）を検出（0012 のようなページ番号は除外）
        // (?:^|\D)0{2,}(?:\D|$) : トークン境界で 2 個以上の 0、後続は非数字または末尾
        // "000" / "image_000" / "p-000" は一致、"0001" / "page0001" は不一致
        if let re = leadingZerosRegex {
            let range = NSRange(location: 0, length: (base as NSString).length)
            if re.firstMatch(in: base, options: [], range: range) != nil { score += 60 }
        } else if lower.hasPrefix("00") || lower.contains("_00") || lower.contains("-00") {
            score += 60
        }

        // ゼロ埋め "1" の手掛かりも弱い表紙シグナルとして再利用（001 を表紙にするアーカイブが多いため）
        if isZeroPaddedOneFilename(path) { score += 50 }

        return score
    }
}

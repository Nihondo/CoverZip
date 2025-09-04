//
//  ZipCore.swift
//  Shared ZIP parsing/extraction utilities for CoverZip
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

/// Options to influence how the first image is picked from a ZIP.
public struct CZFirstImageOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Prefer filenames containing a zero-padded "1" token (e.g. 01, 001, image001) and stop early when found.
    public static let preferZeroPaddedOne = CZFirstImageOptions(rawValue: 1 << 0)
    /// Prefer filenames that look like a cover (e.g. contains "cover", "front", "表紙", or leading 00/000/0000).
    public static let preferCoverLike = CZFirstImageOptions(rawValue: 1 << 1)
}

public enum CZZip {
    /// Read all image entries from ZIP data (sorted naturally by filename)
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

    /// Read all image entries from a ZIP file URL
    public static func imageEntries(from url: URL) -> [CZImageEntry] {
        do { return imageEntries(from: try Data(contentsOf: url, options: [.mappedIfSafe])) }
        catch { NSLog("CZZip read error: \(error)"); return [] }
    }

    /// Read the first image data (by natural sort order) from a ZIP file URL
    public static func firstImageData(from url: URL) -> Data? {
        return imageEntries(from: url).first?.imageData
    }

    /// Read the first image data with an optional early pick rule.
    /// - Parameters:
    ///   - url: ZIP file URL
    ///   - isZeroPaddedFirstPreferred: If true, pick a file whose basename contains a zero-padded "1"
    ///     token (e.g. 01, 001, ...), even when it doesn't start the basename (e.g. "image001").
    ///     This performs an early pick without sorting when such a file exists; otherwise falls back
    ///     to the natural-sort first image.
    /// - Returns: Image data if found; otherwise nil.
    public static func firstImageData(from url: URL, isZeroPaddedFirstPreferred: Bool) -> Data? {
        do { return firstImageData(from: try Data(contentsOf: url, options: [.mappedIfSafe]), isZeroPaddedFirstPreferred: isZeroPaddedFirstPreferred) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /// Read the first image data with option flags (heuristics + natural order fallback).
    public static func firstImageData(from url: URL, options: CZFirstImageOptions) -> Data? {
        do { return firstImageData(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /// Read the first image data with option flags from raw ZIP data.
    public static func firstImageData(from data: Data, options: CZFirstImageOptions) -> Data? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageEntries = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        // 1) Prefer cover-like names first (e.g., "cover", "front", "表紙", or leading 00/000/0000)
        if options.contains(.preferCoverLike) {
            if let best = bestCoverLikeEntry(from: imageEntries) {
                return extractFileData(data: data, entry: best)
            }
        }

        // 2) Otherwise, prefer zero-padded "1" (e.g., 01, 001, image001)
        if options.contains(.preferZeroPaddedOne), let cand = imageEntries.first(where: { isZeroPaddedOneFilename($0.filename) }) {
            return extractFileData(data: data, entry: cand)
        }

        // 3) Fallback: one-pass minimum by NaturalSort (no full sort)
        if let entry = firstImageEntryByNaturalOrderLinear(entries: imageEntries) {
            return extractFileData(data: data, entry: entry)
        }
        return nil
    }

    /// Read the first image entry (filename + data) with option flags.
    public static func firstImageEntry(from url: URL, options: CZFirstImageOptions) -> CZImageEntry? {
        do { return firstImageEntry(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /// Read the first image entry (filename + data) with option flags from raw data.
    public static func firstImageEntry(from data: Data, options: CZFirstImageOptions) -> CZImageEntry? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let images = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        // Choose candidate entry according to options (cover-like has priority over zero-padded "1")
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

    /// Create a thumbnail CGImage for the first image using streaming inflate when compressed.
    /// This avoids full in-memory decompression for large images by attempting incremental decoding
    /// and stopping as soon as a thumbnail becomes available.
    public static func firstImageThumbnail(from url: URL, options: CZFirstImageOptions, maxPixel: Int) -> CGImage? {
        do { return firstImageThumbnail(from: try Data(contentsOf: url, options: [.mappedIfSafe]), options: options, maxPixel: maxPixel) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    public static func firstImageThumbnail(from data: Data, options: CZFirstImageOptions, maxPixel: Int) -> CGImage? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let images = entries.filter { ImageFileFilter.isImagePath($0.filename) }
        guard !images.isEmpty else { return nil }

        // Choose candidate entry (cover-like priority)
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

    /// Return method/fileDataOffset/compressedSize from local header, resolving data descriptor when needed.
    private static func localFileInfo(in data: Data, entry: CZZipEntry) -> (method: UInt16, fileDataOffset: Int, compressedSize: Int)? {
        let off = entry.localHeaderOffset
        guard off + 30 <= data.count else { return nil }
        // Verify local header signature
        let expected: [UInt8] = [0x50, 0x4b, 0x03, 0x04]
        if !data.subdata(in: off..<(off+4)).elementsEqual(expected) { return nil }
        let fnLen = Int(data.subdata(in: off+26..<(off+28)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let exLen = Int(data.subdata(in: off+28..<(off+30)).withUnsafeBytes { $0.load(as: UInt16.self) })
        let method = data.subdata(in: off+8..<(off+10)).withUnsafeBytes { $0.load(as: UInt16.self) }
        let fileDataOffset = off + 30 + fnLen + exLen
        // Use size from central directory when data descriptor is used
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
        // Try incremental source for partial data usage
        let inc1 = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(inc1, imgData, isFinal)
        return CGImageSourceCreateThumbnailAtIndex(inc1, 0, opts)
    }

    /// Stream-inflate DEFLATE-compressed image and attempt incremental thumbnail creation.
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
                    // Update incremental source with partial data (do not finalize; continue streaming)
                    CGImageSourceUpdateData(inc, outData, false)
                }

                if status == COMPRESSION_STATUS_END { break }
                if status == COMPRESSION_STATUS_ERROR { break }
                if streamPtr.pointee.src_size == 0 && status == COMPRESSION_STATUS_OK {
                    // No more input but not ended; break to avoid infinite loop
                    break
                }
            }
        }

        // Finalize and build thumbnail from full data
        CGImageSourceUpdateData(inc, outData, true)
        if let th = CGImageSourceCreateThumbnailAtIndex(inc, 0, thumbOpts) { return th }
        // As a last fallback, create full image (may be heavy)
        return CGImageSourceCreateImageAtIndex(inc, 0, nil)
    }

    /// Read the first image data with an optional early pick rule from raw ZIP data.
    public static func firstImageData(from data: Data, isZeroPaddedFirstPreferred: Bool) -> Data? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageEntries = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        if isZeroPaddedFirstPreferred, let candidate = imageEntries.first(where: { isZeroPaddedOneFilename($0.filename) }) {
            return extractFileData(data: data, entry: candidate)
        }

        // Fallback: decide the first entry by natural sort (filenames only), then extract just that file.
        if let entry = firstImageEntryByNaturalOrderLinear(entries: imageEntries) {
            return extractFileData(data: data, entry: entry)
        }
        return nil
    }

    // MARK: - Low-level ZIP helpers

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
        return compressedData.withUnsafeBytes { bytes in
            let cap = 8 * 1024 * 1024 // 8MB
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
            defer { buffer.deallocate() }
            let decompressedSize = compression_decode_buffer(
                buffer,
                cap,
                bytes.bindMemory(to: UInt8.self).baseAddress!,
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
            if decompressedSize > 0 { return Data(bytes: buffer, count: decompressedSize) }
            return nil
        }
    }

    /// Returns the first image entry by NaturalSort on lastPathComponent, without allocating a sorted array.
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
    /// Pick the most cover-like entry by a simple scoring heuristic.
    /// If multiple entries tie, pick the natural-order minimum among them.
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

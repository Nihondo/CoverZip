//
//  ZipCore.swift
//  Shared ZIP parsing/extraction utilities for CoverZip
//

import Foundation
import Compression

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
        do { return imageEntries(from: try Data(contentsOf: url)) }
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
        do { return firstImageData(from: try Data(contentsOf: url), isZeroPaddedFirstPreferred: isZeroPaddedFirstPreferred) }
        catch { NSLog("CZZip read error: \(error)"); return nil }
    }

    /// Read the first image data with an optional early pick rule from raw ZIP data.
    public static func firstImageData(from data: Data, isZeroPaddedFirstPreferred: Bool) -> Data? {
        guard let cdOffset = findCentralDirectoryOffset(in: data) else { return nil }
        let entries = parseCentralDirectory(data: data, offset: cdOffset)
        let imageEntries = entries.filter { ImageFileFilter.isImagePath($0.filename) }

        if isZeroPaddedFirstPreferred, let candidate = imageEntries.first(where: { isZeroPaddedOneFilename($0.filename) }) {
            return extractFileData(data: data, entry: candidate)
        }

        // Fallback to natural-sort first
        return CZZip.imageEntries(from: data).first?.imageData
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
}

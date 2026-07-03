//
//  CoverSelection.swift
//  CoverZip
//
//  アーカイブ形式に依存しない表紙候補選定とサムネイル生成
//

import Foundation
import ImageIO

/// アーカイブから先頭画像を選ぶ際の方針オプション。
public struct CZFirstImageOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// ゼロ埋めの「1」トークン（例: 01, 001, image001）を含む名前を優先する。
    public static let preferZeroPaddedOne = CZFirstImageOptions(rawValue: 1 << 0)
    /// 表紙らしい名前（例: "cover" / "front" / "表紙" / 先頭 00・000・0000）を優先する。
    public static let preferCoverLike = CZFirstImageOptions(rawValue: 1 << 1)
}

/// 先頭画像サムネイル生成の結果。
public enum CZFirstImageThumbnailResult {
    case thumbnail(CGImage)
    case rawData(Data)
    case none
}

/// ファイル名ベースの表紙候補選定と ImageIO サムネイル生成を提供する。
public enum CZCoverSelector {
    /// オプションに従い、ファイル名配列内の表紙候補インデックスを返す。
    public static func selectIndex(filenames: [String], options: CZFirstImageOptions) -> Int? {
        guard !filenames.isEmpty else { return nil }

        if options.contains(.preferCoverLike), let index = bestCoverLikeIndex(in: filenames) {
            return index
        }
        if options.contains(.preferZeroPaddedOne),
           let index = filenames.firstIndex(where: { isZeroPaddedOneFilename($0) }) {
            return index
        }
        return firstNaturalOrderIndex(in: filenames)
    }

    /// 画像データから指定最大ピクセルに収まるサムネイルを生成する。
    public static func thumbnail(fromImageData imageData: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
            return thumbnail
        }

        let incrementalSource = CGImageSourceCreateIncremental(nil)
        CGImageSourceUpdateData(incrementalSource, imageData as CFData, true)
        return CGImageSourceCreateThumbnailAtIndex(incrementalSource, 0, options)
    }

    private static func firstNaturalOrderIndex(in filenames: [String]) -> Int? {
        guard var bestIndex = filenames.indices.first else { return nil }
        var bestKey = NaturalSort.NaturalSortKey((filenames[bestIndex] as NSString).lastPathComponent)
        for index in filenames.indices.dropFirst() {
            let key = NaturalSort.NaturalSortKey((filenames[index] as NSString).lastPathComponent)
            if key < bestKey {
                bestIndex = index
                bestKey = key
            }
        }
        return bestIndex
    }

    private static let zeroPaddedOneRegex = try? NSRegularExpression(pattern: "(?:^|\\D)0+1(?:\\D|$)")
    private static let leadingZerosRegex = try? NSRegularExpression(pattern: "(?:^|\\D)0{2,}(?:\\D|$)")

    private static func isZeroPaddedOneFilename(_ path: String) -> Bool {
        let last = (path as NSString).lastPathComponent
        let base = (last as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = zeroPaddedOneRegex else {
            return base.contains("001") || base.contains("01")
        }
        let range = NSRange(location: 0, length: (base as NSString).length)
        return regex.firstMatch(in: base, options: [], range: range) != nil
    }

    private static func bestCoverLikeIndex(in filenames: [String]) -> Int? {
        var bestIndex: Int?
        var bestScore = 0

        for (index, filename) in filenames.enumerated() {
            let score = coverLikeScore(for: filename)
            guard score > 0 else { continue }
            if bestIndex == nil
                || score > bestScore
                || (score == bestScore && NaturalSort.lessFilename(
                    (filename as NSString).lastPathComponent,
                    (filenames[bestIndex!] as NSString).lastPathComponent
                )) {
                bestIndex = index
                bestScore = score
            }
        }
        return bestIndex
    }

    private static func coverLikeScore(for path: String) -> Int {
        let last = (path as NSString).lastPathComponent
        let base = (last as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = base.lowercased()
        var score = 0

        if lower.contains("cover") { score += 100 }
        if lower.contains("front") { score += 80 }
        if base.contains("表紙") { score += 100 }

        if let regex = leadingZerosRegex {
            let range = NSRange(location: 0, length: (base as NSString).length)
            if regex.firstMatch(in: base, options: [], range: range) != nil { score += 60 }
        } else if lower.hasPrefix("00") || lower.contains("_00") || lower.contains("-00") {
            score += 60
        }

        if isZeroPaddedOneFilename(path) { score += 50 }
        return score
    }
}

//
//  ImageFileFilter.swift
//  Shared utilities for image path filtering
//

import Foundation

public enum ImageFileFilter {
    private static let imageExtensions: [String] = [
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".tif", ".ico", ".icns"
    ]

    /// Returns true if the path looks like an image file we support.
    /// Rules:
    /// - ignore __MACOSX folder contents
    /// - ignore hidden files (basename starts with ".")
    /// - allow known image extensions (case-insensitive)
    public static func isImagePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if lower.contains("__macosx") { return false }
        let basename = (path as NSString).lastPathComponent
        if basename.hasPrefix(".") { return false }
        return imageExtensions.contains { lower.hasSuffix($0) }
    }
}

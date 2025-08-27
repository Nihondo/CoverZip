//
//  SettingsKeys.swift
//  Shared settings keys and App Group identifier
//

import Foundation

public enum CZSettingsKeys {
    public static let isRightToLeftReading = "isRightToLeftReading"
    public static let sliderVisibilityWidthThreshold = "sliderVisibilityWidthThreshold"
    public static let alwaysSinglePageForCover = "alwaysSinglePageForCover"
    public static let defaultViewMode = "defaultViewMode" // "auto" | "single" | "spread"
    public static let slideshowInterval = "slideshowInterval"
    // Window frame persistence
    public static let restoreWindowFrameEnabled = "restoreWindowFrameEnabled"
    public static let savedWindowFrameString = "savedWindowFrameString"
}

public enum CZAppGroup {
    /// Must match the App Group in entitlements for both App and Extensions
    public static let identifier: String = "group.com.dmng.CoverZip"
}

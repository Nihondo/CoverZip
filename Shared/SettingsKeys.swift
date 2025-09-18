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
    public static let pageTransitionEnabled = "pageTransitionEnabled"
    public static let spreadPairOffset = "spreadPairOffset" // 見開きの左右を補正 (0 or 1)
    // Window frame persistence
    public static let restoreWindowFrameEnabled = "restoreWindowFrameEnabled"
    public static let savedWindowFrameString = "savedWindowFrameString"
    // Reading history
    public static let readingHistoryEnabled = "readingHistoryEnabled"
    public static let readingHistoryData = "readingHistoryData"
    // Image decode/cache policy for preview extension ("noCache" | "deferred" | "immediate")
    public static let imageDecodeCachePolicy = "imageDecodeCachePolicy"
}

public enum CZAppGroup {
    /// Must match the App Group in entitlements for both App and Extensions
    public static let identifier: String = "group.com.dmng.CoverZip"
}

// Distributed notifications used to sync settings across App and Extensions
public enum CZDistributedNotifications {
    // Post this when App-side settings have changed and should be reflected in extensions
    public static let settingsChanged = Notification.Name("com.dmng.CoverZip.settingsChanged")
    // Post this when slider operation completed in Preview Extension (for keyboard focus restoration)
    public static let sliderOperationCompleted = Notification.Name("com.dmng.CoverZip.sliderOperationCompleted")
}

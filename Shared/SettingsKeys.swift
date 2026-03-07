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
    public static let slideshowEnabled = "slideshowEnabled"
    public static let thumbnailStripVisible = "thumbnailStripVisible"
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
    // Thumbnail strip height in the preview extension (CGFloat, default 88)
    public static let thumbnailStripHeight = "thumbnailStripHeight"
}

public enum CZAppGroup {
    /// Must match the App Group in entitlements for both App and Extensions
    public static let identifier: String = "group.com.dmng.CoverZip"
}

public enum CZPreviewSessionCommand: String {
    case setRightToLeftReading
    case setLeftToRightReading
    case setViewModeAuto
    case setViewModeSingle
    case setViewModeSpread
    case setSpreadPairOffset
    case setThumbnailStripVisible
    case setPageTransitionEnabled
    case setSlideshowEnabled
}

public enum CZPreviewSessionCommandUserInfoKeys {
    public static let command = "command"
    public static let boolValue = "boolValue"
    public static let intValue = "intValue"
}

public enum CZPreviewContextMenuEntry: Equatable {
    case action(CZPreviewSessionCommand)
    case separator
}

public enum CZPreviewContextMenuLayout {
    public static let entries: [CZPreviewContextMenuEntry] = [
        .action(.setRightToLeftReading),
        .action(.setLeftToRightReading),
        .separator,
        .action(.setViewModeAuto),
        .action(.setViewModeSingle),
        .action(.setViewModeSpread),
        .separator,
        .action(.setSpreadPairOffset),
        .action(.setThumbnailStripVisible),
        .separator,
        .action(.setPageTransitionEnabled),
        .action(.setSlideshowEnabled),
    ]

    public static func title(for command: CZPreviewSessionCommand) -> String {
        switch command {
        case .setRightToLeftReading:
            return "右綴じ"
        case .setLeftToRightReading:
            return "左綴じ"
        case .setViewModeAuto:
            return "自動"
        case .setViewModeSingle:
            return "単ページ"
        case .setViewModeSpread:
            return "見開き"
        case .setSpreadPairOffset:
            return "見開きの左右を補正"
        case .setThumbnailStripVisible:
            return "サムネイルリスト表示"
        case .setPageTransitionEnabled:
            return "ページ送りアニメ"
        case .setSlideshowEnabled:
            return "スライドショー"
        }
    }
}

// Distributed notifications used to sync settings across App and Extensions
public enum CZDistributedNotifications {
    // Post this when App-side settings have changed and should be reflected in extensions
    public static let settingsChanged = Notification.Name("com.dmng.CoverZip.settingsChanged")
    // Post this when slider operation completed in Preview Extension (for keyboard focus restoration)
    public static let sliderOperationCompleted = Notification.Name("com.dmng.CoverZip.sliderOperationCompleted")
    // Post this when App-side internal viewer menu operation should be reflected in Preview Extension session state
    public static let previewSessionCommand = Notification.Name("com.dmng.CoverZip.previewSessionCommand")
}

//
//  SettingsKeys.swift
//  Shared settings keys and App Group identifier
//

import Foundation

public enum CZLocalized {
    public static func string(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: defaultValue, comment: "")
    }

    public static func formatted(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        let format = string(key, defaultValue: defaultValue)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}

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
    case goToFirstPage
    case goToLastPage
    case jumpRelativePages  // intValue に相対量（正=前進、負=後退）
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
            return CZLocalized.string("context.menu.reading.rtl", defaultValue: "Right to Left")
        case .setLeftToRightReading:
            return CZLocalized.string("context.menu.reading.ltr", defaultValue: "Left to Right")
        case .setViewModeAuto:
            return CZLocalized.string("context.menu.view.auto", defaultValue: "Auto")
        case .setViewModeSingle:
            return CZLocalized.string("context.menu.view.single", defaultValue: "Single Page")
        case .setViewModeSpread:
            return CZLocalized.string("context.menu.view.spread", defaultValue: "Spread")
        case .setSpreadPairOffset:
            return CZLocalized.string("context.menu.spread.offset", defaultValue: "Adjust Spread Pairing")
        case .setThumbnailStripVisible:
            return CZLocalized.string("context.menu.thumbnail.visible", defaultValue: "Show Thumbnail List")
        case .setPageTransitionEnabled:
            return CZLocalized.string("context.menu.page_transition.enabled", defaultValue: "Page Transition Animation")
        case .setSlideshowEnabled:
            return CZLocalized.string("context.menu.slideshow.enabled", defaultValue: "Slideshow")
        case .goToFirstPage:
            return CZLocalized.string("context.menu.page.first", defaultValue: "First Page")
        case .goToLastPage:
            return CZLocalized.string("context.menu.page.last", defaultValue: "Last Page")
        case .jumpRelativePages:
            return CZLocalized.string("context.menu.page.jump", defaultValue: "Jump Pages")
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

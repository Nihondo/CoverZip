//
//  Settings.swift
//  coverZipViewer
//
//  Preview Extension 向け統一設定の軽量ラッパー
//

import Foundation

/// QuickLook Preview Extension用の設定ラッパー
/// CZSettingsへの簡潔なアクセスを提供
final class AppSettings {
    static let shared = AppSettings()

    private let core = CZSettings.shared

    private init() {}

    var isRightToLeftReading: Bool {
        get { core.isRightToLeftReading }
        set { core.isRightToLeftReading = newValue }
    }

    var sliderVisibilityWidthThreshold: Double {
        get { core.sliderVisibilityWidthThreshold }
        set { core.sliderVisibilityWidthThreshold = newValue }
    }

    var alwaysSinglePageForCover: Bool {
        get { core.alwaysSinglePageForCover }
        set { core.alwaysSinglePageForCover = newValue }
    }

    var defaultViewMode: ViewModePreference {
        get { core.defaultViewMode }
        set { core.defaultViewMode = newValue }
    }

    var slideshowInterval: Double {
        get { core.slideshowInterval }
        set { core.slideshowInterval = newValue }
    }

    var isSlideshowEnabled: Bool {
        get { core.isSlideshowEnabled }
        set { core.isSlideshowEnabled = newValue }
    }

    var isThumbnailStripVisible: Bool {
        get { core.isThumbnailStripVisible }
        set { core.isThumbnailStripVisible = newValue }
    }

    var restoreWindowFrameEnabled: Bool {
        get { core.restoreWindowFrameEnabled }
        set { core.restoreWindowFrameEnabled = newValue }
    }

    var savedWindowFrameString: String? {
        get { core.savedWindowFrameString }
        set { core.savedWindowFrameString = newValue }
    }

    var readingHistoryEnabled: Bool {
        get { core.readingHistoryEnabled }
        set { core.readingHistoryEnabled = newValue }
    }

    var imageDecodeCachePolicy: CZImageDecodeCachePolicy {
        get { core.imageDecodeCachePolicy }
        set { core.imageDecodeCachePolicy = newValue }
    }

    var pageTransitionEnabled: Bool {
        get { core.pageTransitionEnabled }
        set { core.pageTransitionEnabled = newValue }
    }

    var spreadPairOffset: Int {
        get { core.spreadPairOffset }
        set { core.spreadPairOffset = newValue }
    }
}

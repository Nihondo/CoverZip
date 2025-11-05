//
//  Settings.swift
//  coverZipViewer
//
//  Lightweight wrapper around unified settings for Preview Extension
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
}

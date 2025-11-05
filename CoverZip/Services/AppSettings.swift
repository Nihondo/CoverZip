//
//  AppSettings.swift
//  CoverZip (App target)
//
//  ObservableObject wrapper around unified settings for SwiftUI
//

import Foundation
import Combine

/// SwiftUI用の設定ラッパー
/// CZSettingsを基に@Published プロパティを提供し、SwiftUIの自動更新に対応
final class AppSettingsWriter: ObservableObject {
    static let shared = AppSettingsWriter()

    private let core = CZSettings.shared

    @Published var isRightToLeftReading: Bool = true {
        didSet { core.isRightToLeftReading = isRightToLeftReading }
    }

    @Published var sliderVisibilityWidthThreshold: Double = 600.0 {
        didSet { core.sliderVisibilityWidthThreshold = sliderVisibilityWidthThreshold }
    }

    @Published var alwaysSinglePageForCover: Bool = true {
        didSet { core.alwaysSinglePageForCover = alwaysSinglePageForCover }
    }

    @Published var defaultViewMode: ViewModePreference = .auto {
        didSet { core.defaultViewMode = defaultViewMode }
    }

    @Published var slideshowInterval: Double = 3.0 {
        didSet { core.slideshowInterval = slideshowInterval }
    }

    @Published var restoreWindowFrameEnabled: Bool = true {
        didSet { core.restoreWindowFrameEnabled = restoreWindowFrameEnabled }
    }

    @Published var imageDecodeCachePolicy: CZImageDecodeCachePolicy = .deferred {
        didSet { core.imageDecodeCachePolicy = imageDecodeCachePolicy }
    }

    private init() {
        // Load current values from core settings
        loadSettings()
    }

    private func loadSettings() {
        isRightToLeftReading = core.isRightToLeftReading
        sliderVisibilityWidthThreshold = core.sliderVisibilityWidthThreshold
        alwaysSinglePageForCover = core.alwaysSinglePageForCover
        slideshowInterval = core.slideshowInterval
        restoreWindowFrameEnabled = core.restoreWindowFrameEnabled
        imageDecodeCachePolicy = core.imageDecodeCachePolicy
        defaultViewMode = core.defaultViewMode
    }

    var savedWindowFrameString: String? {
        get { core.savedWindowFrameString }
        set { core.savedWindowFrameString = newValue }
    }
}

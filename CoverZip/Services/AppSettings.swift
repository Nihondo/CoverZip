//
//  AppSettings.swift
//  CoverZip (App target)
//
//  Shared settings access via UserDefaults (with App Group)
//

import Foundation
import Combine

final class AppSettingsWriter: ObservableObject {
    static let shared = AppSettingsWriter()

    private let defaults: UserDefaults
    
    @Published var isRightToLeftReading: Bool = true {
        didSet { defaults.set(isRightToLeftReading, forKey: CZSettingsKeys.isRightToLeftReading) }
    }
    
    @Published var sliderVisibilityWidthThreshold: Double = 600.0 {
        didSet { defaults.set(sliderVisibilityWidthThreshold, forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) }
    }
    
    @Published var alwaysSinglePageForCover: Bool = true {
        didSet { defaults.set(alwaysSinglePageForCover, forKey: CZSettingsKeys.alwaysSinglePageForCover) }
    }
    
    @Published var defaultViewMode: ViewModePreference = .auto {
        didSet { defaults.set(defaultViewMode.rawValue, forKey: CZSettingsKeys.defaultViewMode) }
    }
    
    @Published var slideshowInterval: Double = 3.0 {
        didSet { defaults.set(slideshowInterval, forKey: CZSettingsKeys.slideshowInterval) }
    }
    
    @Published var restoreWindowFrameEnabled: Bool = true {
        didSet { defaults.set(restoreWindowFrameEnabled, forKey: CZSettingsKeys.restoreWindowFrameEnabled) }
    }

    // プレビュー拡張の画像デコードキャッシュ方針
    @Published var imageDecodeCachePolicy: CZImageDecodeCachePolicy = .deferred {
        didSet { defaults.set(imageDecodeCachePolicy.rawValue, forKey: CZSettingsKeys.imageDecodeCachePolicy) }
    }

    private init() {
    if let shared = UserDefaults(suiteName: CZAppGroup.identifier) {
            self.defaults = shared
        } else {
            self.defaults = .standard
        }
        // Register defaults (same as in extension)
        self.defaults.register(defaults: [
            CZSettingsKeys.isRightToLeftReading: true,
            CZSettingsKeys.sliderVisibilityWidthThreshold: 600.0,
            CZSettingsKeys.alwaysSinglePageForCover: true,
            CZSettingsKeys.defaultViewMode: "auto",
            CZSettingsKeys.slideshowInterval: 3.0,
            CZSettingsKeys.pageTransitionEnabled: true,
            CZSettingsKeys.restoreWindowFrameEnabled: true,
            CZSettingsKeys.imageDecodeCachePolicy: CZImageDecodeCachePolicy.deferred.rawValue
        ])
        
        // Load current values from UserDefaults
        loadSettings()
    }
    
    enum ViewModePreference: String, CaseIterable {
        case auto
        case single
        case spread
    }
    
    private func loadSettings() {
        isRightToLeftReading = defaults.object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool ?? true
        sliderVisibilityWidthThreshold = defaults.object(forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) as? Double ?? 600.0
        alwaysSinglePageForCover = defaults.object(forKey: CZSettingsKeys.alwaysSinglePageForCover) as? Bool ?? true
        slideshowInterval = defaults.object(forKey: CZSettingsKeys.slideshowInterval) as? Double ?? 3.0
        restoreWindowFrameEnabled = defaults.object(forKey: CZSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true
        let rawPolicy = defaults.string(forKey: CZSettingsKeys.imageDecodeCachePolicy) ?? CZImageDecodeCachePolicy.deferred.rawValue
        imageDecodeCachePolicy = CZImageDecodeCachePolicy(rawValue: rawPolicy) ?? .deferred
        
    let rawViewMode = defaults.string(forKey: CZSettingsKeys.defaultViewMode) ?? "auto"
        defaultViewMode = ViewModePreference(rawValue: rawViewMode) ?? .auto
    }

    var savedWindowFrameString: String? {
    get { defaults.string(forKey: CZSettingsKeys.savedWindowFrameString) }
        set {
            if let value = newValue {
                defaults.set(value, forKey: CZSettingsKeys.savedWindowFrameString)
            } else {
                defaults.removeObject(forKey: CZSettingsKeys.savedWindowFrameString)
            }
        }
    }
}

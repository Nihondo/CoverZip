//
//  Settings.swift
//  coverZipViewer
//
//  Shared settings access via UserDefaults (with optional App Group)
//

import Foundation

enum SettingsKeys {
    static let isRightToLeftReading = "isRightToLeftReading"
    static let sliderVisibilityWidthThreshold = "sliderVisibilityWidthThreshold"
    static let alwaysSinglePageForCover = "alwaysSinglePageForCover"
    static let defaultViewMode = "defaultViewMode" // "auto" | "single" | "spread"
    static let slideshowEnabled = "slideshowEnabled"
    static let slideshowInterval = "slideshowInterval"
}

/// App Group identifier placeholder. Set this to your App Group ID (e.g., "group.com.example.CoverZip").
/// If nil, falls back to standard UserDefaults (not shared with app).
enum AppGroup {
    static let identifier: String? = "group.com.dmng.CoverZip"
}

final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    private init() {
        if let groupID = AppGroup.identifier, let shared = UserDefaults(suiteName: groupID) {
            self.defaults = shared
        } else {
            self.defaults = .standard
        }
        // Register defaults
        self.defaults.register(defaults: [
            SettingsKeys.isRightToLeftReading: true,
            SettingsKeys.sliderVisibilityWidthThreshold: 600.0,
            SettingsKeys.alwaysSinglePageForCover: true,
            SettingsKeys.defaultViewMode: "auto",
            SettingsKeys.slideshowEnabled: false,
            SettingsKeys.slideshowInterval: 3.0
        ])
    }

    var isRightToLeftReading: Bool {
        get { defaults.object(forKey: SettingsKeys.isRightToLeftReading) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingsKeys.isRightToLeftReading) }
    }

    var sliderVisibilityWidthThreshold: Double {
        get { defaults.object(forKey: SettingsKeys.sliderVisibilityWidthThreshold) as? Double ?? 600.0 }
        set { defaults.set(newValue, forKey: SettingsKeys.sliderVisibilityWidthThreshold) }
    }

    var alwaysSinglePageForCover: Bool {
        get { defaults.object(forKey: SettingsKeys.alwaysSinglePageForCover) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingsKeys.alwaysSinglePageForCover) }
    }

    enum ViewModePreference: String {
        case auto
        case single
        case spread
    }

    var defaultViewMode: ViewModePreference {
        get {
            let raw = defaults.string(forKey: SettingsKeys.defaultViewMode) ?? "auto"
            return ViewModePreference(rawValue: raw) ?? .auto
        }
        set { defaults.set(newValue.rawValue, forKey: SettingsKeys.defaultViewMode) }
    }

    var slideshowEnabled: Bool {
        get { defaults.object(forKey: SettingsKeys.slideshowEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingsKeys.slideshowEnabled) }
    }

    var slideshowInterval: Double {
        get { defaults.object(forKey: SettingsKeys.slideshowInterval) as? Double ?? 3.0 }
        set { defaults.set(newValue, forKey: SettingsKeys.slideshowInterval) }
    }
}

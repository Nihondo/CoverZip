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
            SettingsKeys.alwaysSinglePageForCover: true
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
}

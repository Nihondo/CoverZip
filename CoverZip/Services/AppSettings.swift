//
//  AppSettings.swift
//  CoverZip (App target)
//
//  Shared settings access via UserDefaults (with App Group)
//

import Foundation

enum AppSettingsKeys {
    static let isRightToLeftReading = "isRightToLeftReading"
    static let sliderVisibilityWidthThreshold = "sliderVisibilityWidthThreshold"
    static let alwaysSinglePageForCover = "alwaysSinglePageForCover"
    static let defaultViewMode = "defaultViewMode" // "auto" | "single" | "spread"
}

/// App Group identifier. Must match entitlements.
enum AppGroupID {
    static let value: String = "group.com.dmng.CoverZip"
}

final class AppSettingsWriter {
    static let shared = AppSettingsWriter()

    private let defaults: UserDefaults

    private init() {
        if let shared = UserDefaults(suiteName: AppGroupID.value) {
            self.defaults = shared
        } else {
            self.defaults = .standard
        }
        // Register defaults (same as in extension)
        self.defaults.register(defaults: [
            AppSettingsKeys.isRightToLeftReading: true,
            AppSettingsKeys.sliderVisibilityWidthThreshold: 600.0,
            AppSettingsKeys.alwaysSinglePageForCover: true,
            AppSettingsKeys.defaultViewMode: "auto"
        ])
    }

    var isRightToLeftReading: Bool {
        get { defaults.object(forKey: AppSettingsKeys.isRightToLeftReading) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppSettingsKeys.isRightToLeftReading) }
    }

    var sliderVisibilityWidthThreshold: Double {
        get { defaults.object(forKey: AppSettingsKeys.sliderVisibilityWidthThreshold) as? Double ?? 600.0 }
        set { defaults.set(newValue, forKey: AppSettingsKeys.sliderVisibilityWidthThreshold) }
    }

    var alwaysSinglePageForCover: Bool {
        get { defaults.object(forKey: AppSettingsKeys.alwaysSinglePageForCover) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppSettingsKeys.alwaysSinglePageForCover) }
    }

    enum ViewModePreference: String {
        case auto
        case single
        case spread
    }

    var defaultViewMode: ViewModePreference {
        get {
            let raw = defaults.string(forKey: AppSettingsKeys.defaultViewMode) ?? "auto"
            return ViewModePreference(rawValue: raw) ?? .auto
        }
        set { defaults.set(newValue.rawValue, forKey: AppSettingsKeys.defaultViewMode) }
    }
}

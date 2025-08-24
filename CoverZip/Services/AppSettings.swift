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
            AppSettingsKeys.sliderVisibilityWidthThreshold: 600.0
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
}

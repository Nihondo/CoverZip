//
//  Settings.swift
//  coverZipViewer
//
//  Shared settings access via UserDefaults (with optional App Group)
//

import Foundation

// Keys and App Group are shared across targets

final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    private init() {
        if let shared = UserDefaults(suiteName: CZAppGroup.identifier) {
            self.defaults = shared
        } else {
            self.defaults = .standard
        }
        // Register defaults
        self.defaults.register(defaults: [
            CZSettingsKeys.isRightToLeftReading: true,
            CZSettingsKeys.sliderVisibilityWidthThreshold: 600.0,
            CZSettingsKeys.alwaysSinglePageForCover: true,
            CZSettingsKeys.defaultViewMode: "auto",
            CZSettingsKeys.slideshowInterval: 3.0,
            CZSettingsKeys.restoreWindowFrameEnabled: true
        ])
    }

    var isRightToLeftReading: Bool {
    get { defaults.object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool ?? true }
    set { defaults.set(newValue, forKey: CZSettingsKeys.isRightToLeftReading) }
    }

    var sliderVisibilityWidthThreshold: Double {
    get { defaults.object(forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) as? Double ?? 600.0 }
    set { defaults.set(newValue, forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) }
    }

    var alwaysSinglePageForCover: Bool {
    get { defaults.object(forKey: CZSettingsKeys.alwaysSinglePageForCover) as? Bool ?? true }
    set { defaults.set(newValue, forKey: CZSettingsKeys.alwaysSinglePageForCover) }
    }

    enum ViewModePreference: String {
        case auto
        case single
        case spread
    }

    var defaultViewMode: ViewModePreference {
        get {
            let raw = defaults.string(forKey: CZSettingsKeys.defaultViewMode) ?? "auto"
            return ViewModePreference(rawValue: raw) ?? .auto
        }
        set { defaults.set(newValue.rawValue, forKey: CZSettingsKeys.defaultViewMode) }
    }

    var slideshowInterval: Double {
    get { defaults.object(forKey: CZSettingsKeys.slideshowInterval) as? Double ?? 3.0 }
    set { defaults.set(newValue, forKey: CZSettingsKeys.slideshowInterval) }
    }

    // MARK: - Window frame persistence
    var restoreWindowFrameEnabled: Bool {
    get { defaults.object(forKey: CZSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: CZSettingsKeys.restoreWindowFrameEnabled) }
    }

    var savedWindowFrameString: String? {
    get { defaults.string(forKey: CZSettingsKeys.savedWindowFrameString) }
        set {
            if let v = newValue {
        defaults.set(v, forKey: CZSettingsKeys.savedWindowFrameString)
            } else {
        defaults.removeObject(forKey: CZSettingsKeys.savedWindowFrameString)
            }
        }
    }
}

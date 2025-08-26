//
//  AppSettings.swift
//  CoverZip (App target)
//
//  Shared settings access via UserDefaults (with App Group)
//

import Foundation
import Combine

enum AppSettingsKeys {
    static let isRightToLeftReading = "isRightToLeftReading"
    static let sliderVisibilityWidthThreshold = "sliderVisibilityWidthThreshold"
    static let alwaysSinglePageForCover = "alwaysSinglePageForCover"
    static let defaultViewMode = "defaultViewMode" // "auto" | "single" | "spread"
    static let slideshowInterval = "slideshowInterval"
    static let restoreWindowFrameEnabled = "restoreWindowFrameEnabled"
    static let savedWindowFrameString = "savedWindowFrameString"
}

/// App Group identifier. Must match entitlements.
enum AppGroupID {
    static let value: String = "group.com.dmng.CoverZip"
}

final class AppSettingsWriter: ObservableObject {
    static let shared = AppSettingsWriter()

    private let defaults: UserDefaults
    
    @Published var isRightToLeftReading: Bool = true {
        didSet { defaults.set(isRightToLeftReading, forKey: AppSettingsKeys.isRightToLeftReading) }
    }
    
    @Published var sliderVisibilityWidthThreshold: Double = 600.0 {
        didSet { defaults.set(sliderVisibilityWidthThreshold, forKey: AppSettingsKeys.sliderVisibilityWidthThreshold) }
    }
    
    @Published var alwaysSinglePageForCover: Bool = true {
        didSet { defaults.set(alwaysSinglePageForCover, forKey: AppSettingsKeys.alwaysSinglePageForCover) }
    }
    
    @Published var defaultViewMode: ViewModePreference = .auto {
        didSet { defaults.set(defaultViewMode.rawValue, forKey: AppSettingsKeys.defaultViewMode) }
    }
    
    @Published var slideshowInterval: Double = 3.0 {
        didSet { defaults.set(slideshowInterval, forKey: AppSettingsKeys.slideshowInterval) }
    }
    
    @Published var restoreWindowFrameEnabled: Bool = true {
        didSet { defaults.set(restoreWindowFrameEnabled, forKey: AppSettingsKeys.restoreWindowFrameEnabled) }
    }

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
            AppSettingsKeys.defaultViewMode: "auto",
            AppSettingsKeys.slideshowInterval: 3.0,
            AppSettingsKeys.restoreWindowFrameEnabled: true
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
        isRightToLeftReading = defaults.object(forKey: AppSettingsKeys.isRightToLeftReading) as? Bool ?? true
        sliderVisibilityWidthThreshold = defaults.object(forKey: AppSettingsKeys.sliderVisibilityWidthThreshold) as? Double ?? 600.0
        alwaysSinglePageForCover = defaults.object(forKey: AppSettingsKeys.alwaysSinglePageForCover) as? Bool ?? true
        slideshowInterval = defaults.object(forKey: AppSettingsKeys.slideshowInterval) as? Double ?? 3.0
        restoreWindowFrameEnabled = defaults.object(forKey: AppSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true
        
        let rawViewMode = defaults.string(forKey: AppSettingsKeys.defaultViewMode) ?? "auto"
        defaultViewMode = ViewModePreference(rawValue: rawViewMode) ?? .auto
    }

    var savedWindowFrameString: String? {
        get { defaults.string(forKey: AppSettingsKeys.savedWindowFrameString) }
        set {
            if let value = newValue {
                defaults.set(value, forKey: AppSettingsKeys.savedWindowFrameString)
            } else {
                defaults.removeObject(forKey: AppSettingsKeys.savedWindowFrameString)
            }
        }
    }
}

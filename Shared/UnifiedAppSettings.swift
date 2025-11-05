//
//  UnifiedAppSettings.swift
//  CoverZip Shared
//
//  Unified settings access layer shared across all targets
//

import Foundation

/// 共有設定アクセスレイヤー
/// App Group経由でUserDefaultsにアクセスし、全ターゲットで一貫した設定管理を提供
public final class CZSettings {

    // MARK: - Shared Instance
    public static let shared = CZSettings()

    private let defaults: UserDefaults

    private init() {
        if let shared = UserDefaults(suiteName: CZAppGroup.identifier) {
            self.defaults = shared
        } else {
            self.defaults = .standard
        }
        registerDefaults()
    }

    // MARK: - Default Registration
    private func registerDefaults() {
        defaults.register(defaults: [
            CZSettingsKeys.isRightToLeftReading: true,
            CZSettingsKeys.sliderVisibilityWidthThreshold: 600.0,
            CZSettingsKeys.alwaysSinglePageForCover: true,
            CZSettingsKeys.defaultViewMode: "auto",
            CZSettingsKeys.slideshowInterval: 3.0,
            CZSettingsKeys.pageTransitionEnabled: true,
            CZSettingsKeys.restoreWindowFrameEnabled: true,
            CZSettingsKeys.readingHistoryEnabled: true,
            CZSettingsKeys.spreadPairOffset: 0,
            CZSettingsKeys.imageDecodeCachePolicy: CZImageDecodeCachePolicy.deferred.rawValue
        ])
    }

    // MARK: - Direct Access to UserDefaults
    public var userDefaults: UserDefaults {
        return defaults
    }

    // MARK: - Reading Direction
    public var isRightToLeftReading: Bool {
        get { defaults.object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.isRightToLeftReading) }
    }

    // MARK: - UI Threshold
    public var sliderVisibilityWidthThreshold: Double {
        get { defaults.object(forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) as? Double ?? 600.0 }
        set { defaults.set(newValue, forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) }
    }

    // MARK: - Cover Page Handling
    public var alwaysSinglePageForCover: Bool {
        get { defaults.object(forKey: CZSettingsKeys.alwaysSinglePageForCover) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.alwaysSinglePageForCover) }
    }

    // MARK: - View Mode
    public var defaultViewMode: ViewModePreference {
        get {
            let raw = defaults.string(forKey: CZSettingsKeys.defaultViewMode) ?? "auto"
            return ViewModePreference(rawValue: raw) ?? .auto
        }
        set { defaults.set(newValue.rawValue, forKey: CZSettingsKeys.defaultViewMode) }
    }

    // MARK: - Slideshow
    public var slideshowInterval: Double {
        get { defaults.object(forKey: CZSettingsKeys.slideshowInterval) as? Double ?? 3.0 }
        set { defaults.set(newValue, forKey: CZSettingsKeys.slideshowInterval) }
    }

    // MARK: - Window Frame Persistence
    public var restoreWindowFrameEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.restoreWindowFrameEnabled) }
    }

    public var savedWindowFrameString: String? {
        get { defaults.string(forKey: CZSettingsKeys.savedWindowFrameString) }
        set {
            if let value = newValue {
                defaults.set(value, forKey: CZSettingsKeys.savedWindowFrameString)
            } else {
                defaults.removeObject(forKey: CZSettingsKeys.savedWindowFrameString)
            }
        }
    }

    // MARK: - Reading History
    public var readingHistoryEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.readingHistoryEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.readingHistoryEnabled) }
    }

    // MARK: - Image Decode Cache Policy
    public var imageDecodeCachePolicy: CZImageDecodeCachePolicy {
        get {
            let raw = defaults.string(forKey: CZSettingsKeys.imageDecodeCachePolicy) ?? CZImageDecodeCachePolicy.deferred.rawValue
            return CZImageDecodeCachePolicy(rawValue: raw) ?? .deferred
        }
        set { defaults.set(newValue.rawValue, forKey: CZSettingsKeys.imageDecodeCachePolicy) }
    }

    // MARK: - Spread Pair Offset
    public var spreadPairOffset: Int {
        get { defaults.object(forKey: CZSettingsKeys.spreadPairOffset) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: CZSettingsKeys.spreadPairOffset) }
    }

    // MARK: - Page Transition
    public var pageTransitionEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.pageTransitionEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.pageTransitionEnabled) }
    }
}

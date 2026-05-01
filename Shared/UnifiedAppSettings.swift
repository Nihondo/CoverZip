//
//  UnifiedAppSettings.swift
//  CoverZip Shared
//
//  全ターゲットで共有する統一設定アクセスレイヤー
//

import Foundation

/// 共有設定アクセスレイヤー
/// App Group経由でUserDefaultsにアクセスし、全ターゲットで一貫した設定管理を提供
public final class CZSettings {

    // MARK: - 共有インスタンス
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

    // MARK: - 既定値登録
    private func registerDefaults() {
        defaults.register(defaults: [
            CZSettingsKeys.isRightToLeftReading: true,
            CZSettingsKeys.sliderVisibilityWidthThreshold: 600.0,
            CZSettingsKeys.alwaysSinglePageForCover: true,
            CZSettingsKeys.defaultViewMode: "auto",
            CZSettingsKeys.slideshowInterval: 3.0,
            CZSettingsKeys.slideshowEnabled: false,
            CZSettingsKeys.thumbnailStripVisible: true,
            CZSettingsKeys.pageTransitionEnabled: true,
            CZSettingsKeys.restoreWindowFrameEnabled: true,
            CZSettingsKeys.readingHistoryEnabled: true,
            CZSettingsKeys.isKeyHelperEnabled: false,
            CZSettingsKeys.keyHelperFinderFallbackEnabled: true,
            CZSettingsKeys.spreadPairOffset: 0,
            CZSettingsKeys.imageDecodeCachePolicy: CZImageDecodeCachePolicy.deferred.rawValue
        ])
    }

    // MARK: - UserDefaults 直接アクセス
    public var userDefaults: UserDefaults {
        return defaults
    }

    // MARK: - 読み方向
    public var isRightToLeftReading: Bool {
        get { defaults.object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.isRightToLeftReading) }
    }

    // MARK: - UI しきい値
    public var sliderVisibilityWidthThreshold: Double {
        get { defaults.object(forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) as? Double ?? 600.0 }
        set { defaults.set(newValue, forKey: CZSettingsKeys.sliderVisibilityWidthThreshold) }
    }

    // MARK: - 表紙ページ処理
    public var alwaysSinglePageForCover: Bool {
        get { defaults.object(forKey: CZSettingsKeys.alwaysSinglePageForCover) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.alwaysSinglePageForCover) }
    }

    // MARK: - 表示モード
    public var defaultViewMode: ViewModePreference {
        get {
            let raw = defaults.string(forKey: CZSettingsKeys.defaultViewMode) ?? "auto"
            return ViewModePreference(rawValue: raw) ?? .auto
        }
        set { defaults.set(newValue.rawValue, forKey: CZSettingsKeys.defaultViewMode) }
    }

    // MARK: - スライドショー
    public var slideshowInterval: Double {
        get { defaults.object(forKey: CZSettingsKeys.slideshowInterval) as? Double ?? 3.0 }
        set { defaults.set(newValue, forKey: CZSettingsKeys.slideshowInterval) }
    }

    public var isSlideshowEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.slideshowEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: CZSettingsKeys.slideshowEnabled) }
    }

    public var isThumbnailStripVisible: Bool {
        get { defaults.object(forKey: CZSettingsKeys.thumbnailStripVisible) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.thumbnailStripVisible) }
    }

    // MARK: - ウィンドウフレーム永続化
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

    // MARK: - 読書履歴
    public var readingHistoryEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.readingHistoryEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.readingHistoryEnabled) }
    }

    // MARK: - Finder QuickLook キー入力ヘルパー
    public var isKeyHelperEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.isKeyHelperEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: CZSettingsKeys.isKeyHelperEnabled) }
    }

    // MARK: - 画像デコードキャッシュ方針
    public var imageDecodeCachePolicy: CZImageDecodeCachePolicy {
        get {
            let raw = defaults.string(forKey: CZSettingsKeys.imageDecodeCachePolicy) ?? CZImageDecodeCachePolicy.deferred.rawValue
            return CZImageDecodeCachePolicy(rawValue: raw) ?? .deferred
        }
        set { defaults.set(newValue.rawValue, forKey: CZSettingsKeys.imageDecodeCachePolicy) }
    }

    // MARK: - 見開きペア補正
    public var spreadPairOffset: Int {
        get { defaults.object(forKey: CZSettingsKeys.spreadPairOffset) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: CZSettingsKeys.spreadPairOffset) }
    }

    // MARK: - ページ遷移
    public var pageTransitionEnabled: Bool {
        get { defaults.object(forKey: CZSettingsKeys.pageTransitionEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: CZSettingsKeys.pageTransitionEnabled) }
    }
}

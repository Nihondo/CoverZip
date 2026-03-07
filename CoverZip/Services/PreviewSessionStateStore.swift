//
//  PreviewSessionStateStore.swift
//  CoverZip
//
//  内蔵ビューアとメニューバー表示メニューが共有するセッション状態の読み出し
//

import Foundation

struct PreviewSessionState {
    let isRightToLeftReading: Bool
    let currentViewMode: ViewModePreference
    let spreadPairOffset: Int
    let isTransitionEnabled: Bool
    let isSlideshowEnabled: Bool
    let isThumbnailStripVisible: Bool
}

enum PreviewSessionStateStore {
    /// 共有設定から Preview セッションの初期状態を読み出す。
    /// - Parameter resetSlideshowState: true の場合は読み出し時に `isSlideshowEnabled` を false へ戻す。
    /// - Note: 呼び出し時に副作用（スライドショー状態のリセット）が発生する点に注意。
    static func loadState(resetSlideshowState: Bool) -> PreviewSessionState {
        let isRightToLeftReading = CZUserDefaults.shared.object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool ?? true
        let currentViewMode = ViewModePreference(
            rawValue: CZUserDefaults.shared.string(forKey: CZSettingsKeys.defaultViewMode) ?? ViewModePreference.auto.rawValue
        ) ?? .auto
        let spreadPairOffset = CZUserDefaults.shared.object(forKey: CZSettingsKeys.spreadPairOffset) as? Int ?? 0
        let isTransitionEnabled = CZUserDefaults.shared.object(forKey: CZSettingsKeys.pageTransitionEnabled) as? Bool ?? true
        let isThumbnailStripVisible = CZSettings.shared.isThumbnailStripVisible
        let isSlideshowEnabled: Bool

        if resetSlideshowState {
            // 新しいセッション開始時は前回のスライドショー継続を防ぐため、強制的に停止状態へ戻す。
            CZSettings.shared.isSlideshowEnabled = false
            isSlideshowEnabled = false
        } else {
            isSlideshowEnabled = CZSettings.shared.isSlideshowEnabled
        }

        return PreviewSessionState(
            isRightToLeftReading: isRightToLeftReading,
            currentViewMode: currentViewMode,
            spreadPairOffset: spreadPairOffset,
            isTransitionEnabled: isTransitionEnabled,
            isSlideshowEnabled: isSlideshowEnabled,
            isThumbnailStripVisible: isThumbnailStripVisible
        )
    }
}

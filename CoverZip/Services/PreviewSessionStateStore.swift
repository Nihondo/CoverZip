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

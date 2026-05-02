//
//  PreviewSessionCommandDispatcher.swift
//  CoverZip
//
//  Previewセッション向け分散通知の送信を一元化する
//

import Foundation

enum PreviewSessionCommandDispatcher {
    /// 読み方向変更を他プロセスへ即時配信する。UserDefaults 同期に依存せず値を直接渡す。
    static func postReadingDirectionChanged(isRightToLeft: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            CZDistributedNotifications.settingsChanged,
            object: nil,
            userInfo: [CZSettingsKeys.isRightToLeftReading: isRightToLeft],
            deliverImmediately: true
        )
    }

    /// 設定変更通知を App/Extension 間へ即時配信する。
    static func postSettingsChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            CZDistributedNotifications.settingsChanged,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func post(
        command: CZPreviewSessionCommand,
        boolValue: Bool? = nil,
        intValue: Int? = nil
    ) {
        // 受信側が型安全に解釈できるよう、command/bool/int の固定キーで payload を構成する。
        var userInfo: [String: Any] = [
            CZPreviewSessionCommandUserInfoKeys.command: command.rawValue
        ]

        if let boolValue {
            userInfo[CZPreviewSessionCommandUserInfoKeys.boolValue] = boolValue
        }
        if let intValue {
            userInfo[CZPreviewSessionCommandUserInfoKeys.intValue] = intValue
        }

        DistributedNotificationCenter.default().postNotificationName(
            CZDistributedNotifications.previewSessionCommand,
            // object にも command を重複格納し、古い受信経路との互換性を維持する。
            object: command.rawValue,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
}

//
//  PreviewSessionCommandDispatcher.swift
//  CoverZip
//
//  Previewセッション向け分散通知の送信を一元化する
//

import Foundation

enum PreviewSessionCommandDispatcher {
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
            object: command.rawValue,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
}

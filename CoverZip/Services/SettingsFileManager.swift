//
//  SettingsFileManager.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation

/**
 * ルーティング設定の読み書きを担当するクラス
 */
class SettingsFileManager {

    /**
     * KeywordSettingsを永続化する
     *
     * @param settings 保存する設定
     * @return 成功した場合はtrue
     */
    @discardableResult
    static func saveSettings(_ settings: KeywordSettings) -> Bool {
        do {
            try settings.save()
            return true
        } catch {
            NSLog("ルーティング設定の保存に失敗しました: \(error.localizedDescription)")
            return false
        }
    }

    /**
     * 設定を読み込む（KeywordSettings.load()のラッパー）
     */
    static func loadSettings() -> KeywordSettings {
        return KeywordSettings.load()
    }
}

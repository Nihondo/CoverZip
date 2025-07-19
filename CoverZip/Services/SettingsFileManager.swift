//
//  SettingsFileManager.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation
import AppKit

/**
 * 設定ファイルの管理を担当するクラス
 * 外部エディタでの編集、再読み込み機能を提供
 */
class SettingsFileManager {
    
    /**
     * settings.jsonファイルのURLを取得
     * 
     * @return settings.jsonファイルのURL（存在しない場合はnil）
     */
    static func getSettingsFileURL() -> URL? {
        return KeywordSettings.getApplicationSupportDirectory()?.appendingPathComponent("settings.json")
    }
    
    /**
     * settings.jsonファイルを外部エディタで開く
     * 
     * @return 開くのに成功した場合はtrue
     */
    static func openSettingsFileInExternalEditor() -> Bool {
        guard let settingsURL = getSettingsFileURL() else {
            NSLog("設定ファイルのURLを取得できませんでした")
            return false
        }
        
        // ファイルが存在しない場合は作成
        if !FileManager.default.fileExists(atPath: settingsURL.path) {
            KeywordSettings.createDefaultSettingsFile()
            NSLog("設定ファイルが存在しないため、デフォルト設定ファイルを作成しました")
        }
        
        do {
            // デフォルトアプリケーションで開く
            try NSWorkspace.shared.open(settingsURL)
            NSLog("設定ファイルを外部エディタで開きました: \(settingsURL.path)")
            return true
        } catch {
            NSLog("設定ファイルを開くのに失敗しました: \(error.localizedDescription)")
            return false
        }
    }
    
    
}
//
//  SettingsCommands.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
//

import SwiftUI

/**
 * アプリケーションの設定関連メニューコマンドを定義
 */
struct SettingsCommands: Commands {
    var body: some Commands {
        CommandMenu("設定") {
            Button("settings.jsonを編集...") {
                openSettingsFile()
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("設定ファイルの場所を表示...") {
                showSettingsFileLocation()
            }
            
            Button("設定を再読み込み") {
                reloadSettings()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
    
    /**
     * settings.jsonファイルを外部エディタで開く
     */
    private func openSettingsFile() {
        let success = SettingsFileManager.openSettingsFileInExternalEditor()
        
        if !success {
            // エラーアラートを表示（オプション）
            NSLog("設定ファイルを開くことができませんでした")
        }
    }
    
    /**
     * 設定ファイルの場所をFinderで表示
     */
    private func showSettingsFileLocation() {
        let success = SettingsFileManager.showSettingsFileInFinder()
        
        if !success {
            NSLog("設定ファイルの場所を表示できませんでした")
        }
    }
    
    /**
     * 設定を再読み込み
     */
    private func reloadSettings() {
        SettingsFileManager.reloadSettings()
        NSLog("設定の再読み込みを実行しました")
    }
}
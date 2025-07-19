//
//  CoverZipApp.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/15.
//

import SwiftUI

@main
struct CoverZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // 初回起動時にデフォルト設定ファイルを作成
        createDefaultSettingsIfNeeded()
    }
    
    var body: some Scene {
        Settings {
            VStack {
                Text("CoverZip設定")
                    .font(.title)
                Text("ZIPファイルルーティングアプリケーション")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("設定ファイルを編集") {
                    let _ = SettingsFileManager.openSettingsFileInExternalEditor()
                }
                .padding(.top)
            }
            .padding()
            .frame(width: 300, height: 150)
        }
    }
    
    /**
     * デフォルト設定ファイルが存在しない場合に作成する
     */
    private func createDefaultSettingsIfNeeded() {
        let settings = KeywordSettings.load()
        
        // デフォルト設定（空）の場合は、サンプル設定を作成
        if settings.keywords.isEmpty && settings.default.isEmpty {
            KeywordSettings.createDefaultSettingsFile()
        }
    }
}

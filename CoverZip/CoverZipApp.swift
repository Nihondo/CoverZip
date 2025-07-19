//
//  CoverZipApp.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/15.
//

import SwiftUI

@main
struct CoverZipApp: App {
    
    init() {
        // 初回起動時にデフォルト設定ファイルを作成
        createDefaultSettingsIfNeeded()
    }
    
    var body: some Scene {
        DocumentGroup(newDocument: CoverZipDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            SettingsCommands()
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

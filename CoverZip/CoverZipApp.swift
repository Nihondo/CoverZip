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
            TabView {
                RoutingSettingsView()
                    .tabItem {
                        Label("ファイルルーティング", systemImage: "arrow.triangle.branch")
                    }
                
                if #available(macOS 13.0, *) {
                    PreviewSettingsView()
                        .tabItem {
                            Label("プレビュー設定", systemImage: "eye")
                        }
                } else {
                    // Fallback on earlier versions
                }
            }
            .frame(minWidth: 650, minHeight: 500)
        }
        .commands {
            FileMenuCommands()
            #if DEBUG
            DebugMenuCommands()
            #endif
        }
    }
    
    /**
     * デフォルト設定ファイルが存在しない場合に作成する
     */
    private func createDefaultSettingsIfNeeded() {
        let settings = KeywordSettings.load()

        // デフォルト設定（空）の場合は、サンプル設定を作成
        if settings.rules.isEmpty && settings.defaultApplication.isEmpty {
            KeywordSettings.createDefaultSettingsFile()
        }
    }
}

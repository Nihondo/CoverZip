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
        // 初回起動時にルーティング設定の初期値を投入
        seedRoutingSettingsIfNeeded()
    }
    
    var body: some Scene {
    Settings {
            TabView {
                if #available(macOS 13.0, *) {
                    PreviewSettingsView()
                        .tabItem {
                            Label(CZLocalized.string("app.tab.viewer", defaultValue: "Viewer Settings"), systemImage: "eye")
                        }
                } else {
                    // 旧バージョン向けフォールバック
                }

                RoutingSettingsView()
                    .tabItem {
                        Label(CZLocalized.string("app.tab.routing", defaultValue: "File Routing"), systemImage: "arrow.triangle.branch")
                    }
            }
            .frame(minWidth: 650, minHeight: 500)
        }
        .commands {
            FileMenuCommands()
            ViewMenuCommands()
        }
    }
    
    /// ルーティング設定が未設定の場合にサンプル設定を投入する
    private func seedRoutingSettingsIfNeeded() {
        KeywordSettings.seedDefaultSettingsIfNeeded()
    }
}

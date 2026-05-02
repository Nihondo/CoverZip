//
//  CoverZipApp.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/15.
//

import SwiftUI

enum AppWindowIdentifier {
    static let settings = "settings-window"
}

private enum SettingsTab: Hashable, CaseIterable {
    case viewer
    case slideshow
    case window
    case update
    case routing

    var title: String {
        switch self {
        case .viewer:
            CZLocalized.string("app.tab.viewer", defaultValue: "Viewer Settings")
        case .slideshow:
            CZLocalized.string("app.tab.slideshow", defaultValue: "Slideshow")
        case .window:
            CZLocalized.string("app.tab.window", defaultValue: "Window")
        case .update:
            CZLocalized.string("app.tab.update", defaultValue: "Update")
        case .routing:
            CZLocalized.string("app.tab.routing", defaultValue: "File Routing")
        }
    }

    var systemImage: String {
        switch self {
        case .viewer:
            "eye"
        case .slideshow:
            "play.rectangle"
        case .window:
            "macwindow"
        case .update:
            "arrow.down.circle"
        case .routing:
            "arrow.triangle.branch"
        }
    }
}

private struct SettingsRootView: View {
    @State private var selectedSettingsTab: SettingsTab? = .viewer

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $selectedSettingsTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            detailView
        }
        .frame(minWidth: 1000, minHeight: 560)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSettingsTab {
        case .viewer, .none:
            PreviewSettingsView()
        case .slideshow:
            SlideshowSettingsView()
        case .window:
            WindowSettingsView()
        case .update:
            UpdateSettingsView(releasesURL: URL(string: "https://github.com/Nihondo/CoverZip/releases")!)
        case .routing:
            RoutingSettingsView()
        }
    }
}

@main
struct CoverZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // 初回起動時にルーティング設定の初期値を投入
        seedRoutingSettingsIfNeeded()
        _ = AppUpdateController.shared
    }
    
    var body: some Scene {
        Window(
            CZLocalized.string("window.settings.title", defaultValue: "CoverZip Settings"),
            id: AppWindowIdentifier.settings
        ) {
            SettingsRootView()
        }
        .defaultSize(width: 1000, height: 560)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        .commands {
            FileMenuCommands()
            SettingsMenuCommands()
            ViewMenuCommands()
        }
    }
    
    /// ルーティング設定が未設定の場合にサンプル設定を投入する
    private func seedRoutingSettingsIfNeeded() {
        KeywordSettings.seedDefaultSettingsIfNeeded()
    }
}

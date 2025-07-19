//
//  CoverZipApp.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/15.
//

import SwiftUI
import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("CoverZipアプリケーション起動完了")
        
        // Launch Servicesの状態を確認
        let bundle = Bundle.main
        NSLog("Bundle ID: \(bundle.bundleIdentifier ?? "不明")")
        NSLog("Bundle Path: \(bundle.bundlePath)")
        
        // ファイル処理の準備
        NSApplication.shared.servicesProvider = self
    }
    
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSLog("applicationShouldOpenUntitledFile呼び出し")
        return false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSLog("applicationShouldTerminateAfterLastWindowClosed呼び出し")
        return false
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        NSLog("application:openFile呼び出し: \(filename)")
        return processZipFile(at: URL(fileURLWithPath: filename))
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        NSLog("application:openFiles呼び出し: \(filenames)")
        for filename in filenames {
            _ = processZipFile(at: URL(fileURLWithPath: filename))
        }
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        NSLog("application:open:urls呼び出し: \(urls)")
        for url in urls {
            _ = processZipFile(at: url)
        }
    }
    
    func application(_ sender: NSApplication, openTempFile filename: String) -> Bool {
        NSLog("application:openTempFile呼び出し: \(filename)")
        return processZipFile(at: URL(fileURLWithPath: filename))
    }
    
    private func processZipFile(at url: URL) -> Bool {
        // ZIPファイルのみを処理
        guard url.pathExtension.lowercased() == "zip" else { 
            NSLog("ZIPファイルではありません: \(url.lastPathComponent)")
            return false 
        }
        
        NSLog("ZIPファイルを処理開始: \(url.lastPathComponent)")
        
        // キーワードマッチングと外部アプリケーション起動を実行
        let originalFileName = url.lastPathComponent
        let settings = KeywordSettings.load()
        
        do {
            // ファイルデータを読み込み
            let data = try Data(contentsOf: url)
            
            // 一時ファイルを作成
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("zip")
            
            try data.write(to: tempURL)
            
            // キーワードマッチングを実行
            let matchResult = KeywordMatcher.findMatchingApplication(
                for: tempURL,
                originalFileName: originalFileName,
                using: settings
            )
            
            // 外部アプリケーションで開く
            if let application = matchResult.matchedApplication {
                NSLog("外部アプリケーション起動: \(application)")
                _ = AppLauncher.launchApplication(with: tempURL, applicationName: application)
            } else {
                NSLog("デフォルトアプリケーション起動")
                _ = AppLauncher.launchWithDefaultApplication(zipFileURL: tempURL)
            }
            
            // 遅延削除
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            return true
        } catch {
            NSLog("ファイル処理に失敗: \(error)")
            return false
        }
    }
}

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
            }
            .padding()
            .frame(width: 300, height: 100)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("設定") {
                Button("設定ファイルを編集...") {
                    let _ = SettingsFileManager.openSettingsFileInExternalEditor()
                }
                .keyboardShortcut(",", modifiers: .command)
                
                Button("設定を再読み込み") {
                    SettingsFileManager.reloadSettings()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
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

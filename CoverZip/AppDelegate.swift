//
//  AppDelegate.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
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
        
        // キーワードマッチングを実行
        let fileName = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        let parentFolder = url.deletingLastPathComponent().lastPathComponent
        let fileExtension = url.pathExtension
        let matchResult = KeywordMatcher.checkKeyword(for: fileName, parentFolder: parentFolder, fileExtension: fileExtension, using: settings)
        
        // ルーティング結果に基づいて起動
        if let application = matchResult.matchedApplication, !application.isEmpty {
            if application.lowercased() == "internal" {
                NSLog("内蔵ビューアで表示: internal")
                InternalViewer.shared.show(url: url)
                return true
            } else {
                NSLog("外部アプリケーション起動: \(application)")
                _ = AppLauncher.launchApplication(with: url, applicationName: application)
            }
        } else {
            NSLog("デフォルトアプリケーション起動")
            _ = AppLauncher.launchWithDefaultApplication(zipFileURL: url)
        }
        
    NSLog("外部アプリケーション起動、CoverZipを終了します")
    NSApplication.shared.terminate(nil)
        
        return true
    }
}
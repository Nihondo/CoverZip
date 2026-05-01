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
        KeyHelperManager.shared.repairRegistrationIfNeeded()
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
        // Finder の「このアプリケーションで開く」など単一ファイル経路。
        NSLog("application:openFile呼び出し: \(filename)")
        return processZipFile(at: URL(fileURLWithPath: filename))
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        // 複数選択オープン経路。各ファイルを同じ判定ロジックへ集約する。
        NSLog("application:openFiles呼び出し: \(filenames)")
        for filename in filenames {
            _ = processZipFile(at: URL(fileURLWithPath: filename))
        }
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        // URL ベースオープン経路（LaunchServices 経由）
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
        // 判定（route）と実行（handle）を分離したサービスへ委譲し、
        // AppDelegate 側はライフサイクル制御（終了判定）に専念する。
        let decision = ZipRoutingService.route(zipURL: url, invocationContext: .appLaunch)
        let isHandled = ZipRoutingService.handle(decision)
        guard isHandled else { return false }

        if ZipRoutingService.shouldTerminateAfterHandling(decision, invocationContext: .appLaunch) {
            NSLog("外部アプリケーション起動、CoverZipを終了します")
            NSApplication.shared.terminate(nil)
        }

        return true
    }
}

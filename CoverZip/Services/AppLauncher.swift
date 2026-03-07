//
//  AppLauncher.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
//

import Foundation
import AppKit

/**
 * アプリケーション起動処理の結果を表す列挙型
 */
enum AppLaunchResult {
    case success
    case applicationNotFound
    case fileNotFound
    case launchFailed(Error)
}

/**
 * 外部アプリケーション起動を担当するクラス
 */
class AppLauncher {
    
    /**
     * 指定されたアプリケーションでZIPファイルを開く
     * 
     * @param zipFileURL 開くZIPファイルのURL
     * @param applicationName アプリケーション名（例: "Archive Utility.app"）
     * @return 起動結果
     */
    static func launchApplication(
        with zipFileURL: URL,
        applicationName: String
    ) -> AppLaunchResult {
        
        // アプリケーション名が空の場合
        if applicationName.isEmpty {
            return .applicationNotFound
        }
        
        // ZIPファイルが存在するかチェック
        guard FileManager.default.fileExists(atPath: zipFileURL.path) else {
            return .fileNotFound
        }
        
        // アプリケーションのURLを取得
        guard let applicationURL = findApplicationURL(applicationName: applicationName) else {
            return .applicationNotFound
        }

        // アプリケーションでファイルを開く（macOS 11以降のAPI）
        if let launchError = openURLs([zipFileURL], withApplicationAt: applicationURL) {
            return .launchFailed(launchError)
        }

        return .success
    }
    
    /**
     * デフォルトアプリケーションでZIPファイルを開く
     *
     * @param zipFileURL 開くZIPファイルのURL
     * @return 起動結果
     */
    static func launchWithDefaultApplication(zipFileURL: URL) -> AppLaunchResult {
        guard FileManager.default.fileExists(atPath: zipFileURL.path) else {
            return .fileNotFound
        }
        
        let success = NSWorkspace.shared.open(zipFileURL)
        if success {
            return .success
        } else {
            let error = NSError(
                domain: "AppLauncher",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: CZLocalized.string(
                    "error.app_launcher.cannot_open_file",
                    defaultValue: "Could not open file"
                )]
            )
            return .launchFailed(error)
        }
    }
    
    /**
     * アプリケーション名からアプリケーションのURLを検索する
     * 
     * @param applicationName アプリケーション名
     * @return アプリケーションのURL（見つからない場合はnil）
     */
    private static func findApplicationURL(applicationName: String) -> URL? {
        let workspace = NSWorkspace.shared
        
        // .appが付いていない場合は追加
        let appName = applicationName.hasSuffix(".app") ? applicationName : "\(applicationName).app"
        
        // 絶対パスの場合
        if applicationName.hasPrefix("/") {
            let url = URL(fileURLWithPath: applicationName)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        
        // アプリケーション名からURLを検索
        if let url = workspace.urlForApplication(withBundleIdentifier: appName) {
            return url
        }
        
        // Applications フォルダで検索
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        let appURL = applicationsURL.appendingPathComponent(appName)
        if FileManager.default.fileExists(atPath: appURL.path) {
            return appURL
        }
        
        // ユーザーのApplications フォルダで検索
        if let userApplicationsURL = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            let userAppURL = userApplicationsURL.appendingPathComponent(appName)
            if FileManager.default.fileExists(atPath: userAppURL.path) {
                return userAppURL
            }
        }
        
        return nil
    }

    private static func openURLs(_ urls: [URL], withApplicationAt applicationURL: URL) -> Error? {
        let configuration = NSWorkspace.OpenConfiguration()
        let semaphore = DispatchSemaphore(value: 0)
        var launchError: Error?

        NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, error in
            launchError = error
            semaphore.signal()
        }

        let timeout = DispatchTime.now() + .seconds(5)
        if semaphore.wait(timeout: timeout) == .timedOut {
            return NSError(
                domain: "AppLauncher",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: CZLocalized.string(
                    "error.app_launcher.launch_timeout",
                    defaultValue: "Application launch timed out"
                )]
            )
        }
        return launchError
    }
    
}

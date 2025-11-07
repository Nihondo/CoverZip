//
//  FileOpenPanelService.swift
//  CoverZip
//
//  NSOpenPanel から ZIP を選んで起動ルーティングを行う
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum FileOpenPanelService {

    /// 内蔵ビューアで開く（常に内蔵ビューアで表示）
    static func presentAndOpenZip() {
        let panel = createOpenPanel()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            openZipInInternalViewer(at: url)
        }
    }

    /// ファイルを開く（マッチング処理を実行）
    static func presentAndRouteZip() {
        let panel = createOpenPanel()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            routeAndOpenZip(at: url)
        }
    }

    // MARK: - Private Methods

    /// NSOpenPanelを作成
    private static func createOpenPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType.zip]
        } else {
            panel.allowedFileTypes = ["zip"]
        }
        panel.level = .modalPanel
        return panel
    }

    /// 内蔵ビューアで開く
    private static func openZipInInternalViewer(at url: URL) {
        guard url.pathExtension.lowercased() == "zip" else { return }
        InternalViewer.shared.show(url: url)
    }

    /// マッチング処理を実行してファイルを開く（AppDelegateと同じロジック）
    private static func routeAndOpenZip(at url: URL) {
        guard url.pathExtension.lowercased() == "zip" else { return }

        NSLog("ZIPファイルを処理開始: \(url.lastPathComponent)")

        // キーワードマッチングと外部アプリケーション起動を実行
        let originalFileName = url.lastPathComponent
        let settings = KeywordSettings.load()

        // キーワードマッチングを実行（ファイル名とパス名の両方を使用）
        let fileName = URL(fileURLWithPath: originalFileName).deletingPathExtension().lastPathComponent
        let fullPath = url.path
        let matchResult = KeywordMatcher.checkKeyword(for: fileName, fullPath: fullPath, using: settings)

        // ルーティング結果に基づいて起動
        if let application = matchResult.matchedApplication, !application.isEmpty {
            if application.lowercased() == "internal" {
                NSLog("内蔵ビューアで表示: internal")
                InternalViewer.shared.show(url: url)
                return
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
    }
}

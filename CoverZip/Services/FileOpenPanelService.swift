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

    // MARK: - 非公開メソッド

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
        let decision = ZipRoutingService.route(zipURL: url, invocationContext: .openPanelRouting)
        let isHandled = ZipRoutingService.handle(decision)
        guard isHandled else { return }

        if ZipRoutingService.shouldTerminateAfterHandling(decision, invocationContext: .openPanelRouting) {
            NSLog("外部アプリケーション起動、CoverZipを終了します")
            NSApplication.shared.terminate(nil)
        }
    }
}

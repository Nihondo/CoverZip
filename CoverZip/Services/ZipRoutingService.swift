//
//  ZipRoutingService.swift
//  CoverZip
//
//  アーカイブルーティング判定と実行を統合するサービス
//

import AppKit
import Foundation

enum RouteInvocationContext {
    case appLaunch
    case openPanelRouting
}

enum RouteDecision {
    case openInternalViewer(archiveURL: URL)
    case openExternalApp(archiveURL: URL, applicationName: String)
    case openDefaultApp(archiveURL: URL)
    case ignore
}

enum ZipRoutingService {

    /// アーカイブ 1件に対する「判定フェーズ」。
    /// - Note: ここでは起動は行わず、あくまで `RouteDecision` を返すだけにして
    ///   判定と実行を分離することで、呼び出し元（App起動/ファイルパネル）ごとの差分を最小化している。
    static func route(zipURL archiveURL: URL, invocationContext: RouteInvocationContext) -> RouteDecision {
        let contextLabel: String
        switch invocationContext {
        case .appLaunch:
            contextLabel = "appLaunch"
        case .openPanelRouting:
            contextLabel = "openPanelRouting"
        }
        let resourceValues = try? archiveURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if resourceValues?.isDirectory == true, resourceValues?.isPackage != true {
            NSLog("フォルダを内蔵ビューアで表示 [%@]: %@", contextLabel, archiveURL.lastPathComponent)
            return .openInternalViewer(archiveURL: archiveURL)
        }

        guard CZArchiveKind.kind(forExtensionOf: archiveURL) != nil else {
            NSLog("対応対象ではありません: %@", archiveURL.lastPathComponent)
            return .ignore
        }

        NSLog("アーカイブファイルを処理開始 [%@]: %@", contextLabel, archiveURL.lastPathComponent)

        let settings = KeywordSettings.load()
        // 先勝ちマッチング: 上から評価し、最初に一致したルールの application を採用する。
        let matchResult = KeywordMatcher.checkKeyword(for: archiveURL, using: settings)

        guard let applicationName = matchResult.matchedApplication, !applicationName.isEmpty else {
            NSLog("デフォルトアプリケーション起動")
            return .openDefaultApp(archiveURL: archiveURL)
        }

        if applicationName.lowercased() == "internal" {
            NSLog("内蔵ビューアで表示: internal")
            return .openInternalViewer(archiveURL: archiveURL)
        }

        NSLog("外部アプリケーション起動: %@", applicationName)
        return .openExternalApp(archiveURL: archiveURL, applicationName: applicationName)
    }

    /// `RouteDecision` を実行するフェーズ。
    /// - Returns: 実際に何らかの処理（起動/表示）を実行した場合 true。
    @discardableResult
    static func handle(_ decision: RouteDecision) -> Bool {
        switch decision {
        case .openInternalViewer(let archiveURL):
            InternalViewer.shared.show(url: archiveURL)
            return true
        case .openExternalApp(let archiveURL, let applicationName):
            _ = AppLauncher.launchApplication(with: archiveURL, applicationName: applicationName)
            return true
        case .openDefaultApp(let archiveURL):
            _ = AppLauncher.launchWithDefaultApplication(zipFileURL: archiveURL)
            return true
        case .ignore:
            return false
        }
    }

    /// 実行後に CoverZip 本体を終了すべきかを判定する。
    /// - Note: 外部/既定アプリ起動時のみ終了し、内蔵ビューア表示時は常駐させる。
    static func shouldTerminateAfterHandling(_ decision: RouteDecision, invocationContext: RouteInvocationContext) -> Bool {
        switch invocationContext {
        case .appLaunch, .openPanelRouting:
            switch decision {
            case .openExternalApp, .openDefaultApp:
                return true
            case .openInternalViewer, .ignore:
                return false
            }
        }
    }
}

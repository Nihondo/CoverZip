//
//  ZipRoutingService.swift
//  CoverZip
//
//  ZIPルーティング判定と実行を統合するサービス
//

import AppKit
import Foundation

enum RouteInvocationContext {
    case appLaunch
    case openPanelRouting
}

enum RouteDecision {
    case openInternalViewer(zipURL: URL)
    case openExternalApp(zipURL: URL, applicationName: String)
    case openDefaultApp(zipURL: URL)
    case ignore
}

enum ZipRoutingService {

    /// ZIP 1件に対する「判定フェーズ」。
    /// - Note: ここでは起動は行わず、あくまで `RouteDecision` を返すだけにして
    ///   判定と実行を分離することで、呼び出し元（App起動/ファイルパネル）ごとの差分を最小化している。
    static func route(zipURL: URL, invocationContext: RouteInvocationContext) -> RouteDecision {
        let contextLabel: String
        switch invocationContext {
        case .appLaunch:
            contextLabel = "appLaunch"
        case .openPanelRouting:
            contextLabel = "openPanelRouting"
        }
        guard zipURL.pathExtension.lowercased() == "zip" else {
            NSLog("ZIPファイルではありません: %@", zipURL.lastPathComponent)
            return .ignore
        }

        NSLog("ZIPファイルを処理開始 [%@]: %@", contextLabel, zipURL.lastPathComponent)

        let settings = KeywordSettings.load()
        // 先勝ちマッチング: 上から評価し、最初に一致したルールの application を採用する。
        let matchResult = KeywordMatcher.checkKeyword(for: zipURL, using: settings)

        guard let applicationName = matchResult.matchedApplication, !applicationName.isEmpty else {
            NSLog("デフォルトアプリケーション起動")
            return .openDefaultApp(zipURL: zipURL)
        }

        if applicationName.lowercased() == "internal" {
            NSLog("内蔵ビューアで表示: internal")
            return .openInternalViewer(zipURL: zipURL)
        }

        NSLog("外部アプリケーション起動: %@", applicationName)
        return .openExternalApp(zipURL: zipURL, applicationName: applicationName)
    }

    /// `RouteDecision` を実行するフェーズ。
    /// - Returns: 実際に何らかの処理（起動/表示）を実行した場合 true。
    @discardableResult
    static func handle(_ decision: RouteDecision) -> Bool {
        switch decision {
        case .openInternalViewer(let zipURL):
            InternalViewer.shared.show(url: zipURL)
            return true
        case .openExternalApp(let zipURL, let applicationName):
            _ = AppLauncher.launchApplication(with: zipURL, applicationName: applicationName)
            return true
        case .openDefaultApp(let zipURL):
            _ = AppLauncher.launchWithDefaultApplication(zipFileURL: zipURL)
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

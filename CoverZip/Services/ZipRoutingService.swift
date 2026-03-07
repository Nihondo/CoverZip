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

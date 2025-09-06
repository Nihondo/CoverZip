//
//  QLPreviewSmokeTest.swift (shim)
//  CoverZip
//
//  2025-09-06: 旧名からの移行用シム。正式実装は `QLPreviewInputDriver`。
//  Xcode プロジェクトの参照更新が済むまで一時的に残します。

import Foundation

@available(*, deprecated, message: "Use QLPreviewInputDriver instead.")
enum QLPreviewSmokeTest {}

// 型エイリアスで後方互換（旧呼び出し箇所のビルドを維持）
typealias QLPreviewSmokeTestAlias = QLPreviewInputDriver

// 既存コードの呼び出しに備え、静的メソッドを転送
extension QLPreviewSmokeTest {
    static func presentAndOpen() {
        QLPreviewInputDriver.presentAndOpen()
    }
    static func openQuickLookWindow(url: URL, enableKeyMonitors: Bool = false) {
        QLPreviewInputDriver.openQuickLookWindow(url: url, enableKeyMonitors: enableKeyMonitors)
    }
}

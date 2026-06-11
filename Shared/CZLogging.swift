//
//  CZLogging.swift
//  ホットパスでの詳細ログ出力を制御する共有ユーティリティ
//

import Foundation

/// 詳細ログ（マウスイベント・デコード毎などホットパスでの NSLog）の出力可否
public enum CZVerboseLog {
    /// Debugビルド、または環境変数 `CZ_VERBOSE_LOG=1` が設定されている場合に true
    public static let isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["CZ_VERBOSE_LOG"] == "1"
        #endif
    }()
}

/// `CZVerboseLog.isEnabled` が true の場合のみ `NSLog` と同じ書式でログを出力する
public func verboseLog(_ format: String, _ args: CVarArg...) {
    guard CZVerboseLog.isEnabled else { return }
    withVaList(args) { NSLogv(format, $0) }
}

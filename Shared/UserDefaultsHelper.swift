//
//  UserDefaultsHelper.swift
//  CoverZip Shared
//
//  Centralized UserDefaults access for App Group
//

import Foundation

/// App Group共有UserDefaultsへの統一アクセスポイント
public enum CZUserDefaults {
    /// App Group共有のUserDefaultsインスタンス
    /// フォールバックとして標準UserDefaultsを使用
    public static var shared: UserDefaults {
        UserDefaults(suiteName: CZAppGroup.identifier) ?? .standard
    }
}

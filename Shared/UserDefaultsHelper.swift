//
//  UserDefaultsHelper.swift
//  CoverZip Shared
//
//  App Group 用 UserDefaults アクセスの共通化
//

import Foundation

/// App Group共有UserDefaultsへの統一アクセスポイント
public enum CZUserDefaults {
    /// App Group共有のUserDefaultsインスタンス
    /// フォールバックとして標準UserDefaultsを使用
    public static let shared: UserDefaults = UserDefaults(suiteName: CZAppGroup.identifier) ?? .standard
}

//
//  ViewModePreference.swift
//  CoverZip Shared
//
//  View mode preference enumeration shared across all targets
//

import Foundation

/// 表示モード設定
/// - auto: 自動（画像サイズに応じて判定）
/// - single: 単ページ表示
/// - spread: 見開き表示
public enum ViewModePreference: String, CaseIterable, Codable {
    case auto
    case single
    case spread
}

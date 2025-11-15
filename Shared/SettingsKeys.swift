//
//  SettingsKeys.swift
//  共有設定キーとApp Group識別子
//

import Foundation

/**
 * 設定キー定義
 *
 * 全ターゲットで使用する設定キーの一元管理
 */
public enum CZSettingsKeys {
    public static let isRightToLeftReading = "isRightToLeftReading"
    public static let sliderVisibilityWidthThreshold = "sliderVisibilityWidthThreshold"
    public static let alwaysSinglePageForCover = "alwaysSinglePageForCover"
    public static let defaultViewMode = "defaultViewMode" // "auto" | "single" | "spread"
    public static let slideshowInterval = "slideshowInterval"
    public static let pageTransitionEnabled = "pageTransitionEnabled"
    public static let spreadPairOffset = "spreadPairOffset" // 見開きの左右を補正 (0 or 1)

    // ウィンドウフレーム永続化
    public static let restoreWindowFrameEnabled = "restoreWindowFrameEnabled"
    public static let savedWindowFrameString = "savedWindowFrameString"

    // 読書履歴
    public static let readingHistoryEnabled = "readingHistoryEnabled"
    public static let readingHistoryData = "readingHistoryData"

    // 画像デコード/キャッシュポリシー（プレビュー拡張用）: "noCache" | "deferred" | "immediate"
    public static let imageDecodeCachePolicy = "imageDecodeCachePolicy"
}

/**
 * App Group設定
 *
 * メインアプリと拡張機能間でデータを共有するためのApp Group識別子
 */
public enum CZAppGroup {
    /// EntitlementsでAppと拡張機能の両方に設定されているApp Groupと一致する必要がある
    public static let identifier: String = "group.com.dmng.CoverZip"
}

/**
 * 分散通知定義
 *
 * アプリと拡張機能間で設定を同期するために使用
 */
public enum CZDistributedNotifications {
    /// アプリ側の設定が変更され、拡張機能に反映すべき場合に送信
    public static let settingsChanged = Notification.Name("com.dmng.CoverZip.settingsChanged")

    /// プレビュー拡張でスライダー操作が完了した際に送信（キーボードフォーカス復元用）
    public static let sliderOperationCompleted = Notification.Name("com.dmng.CoverZip.sliderOperationCompleted")
}

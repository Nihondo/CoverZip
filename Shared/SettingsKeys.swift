//
//  SettingsKeys.swift
//  共有設定キーと App Group 識別子
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum CZLocalized {
    public static func string(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: defaultValue, comment: "")
    }

    public static func formatted(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        let format = string(key, defaultValue: defaultValue)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}

public enum CZSettingsKeys {
    public static let isRightToLeftReading = "isRightToLeftReading"
    public static let sliderVisibilityWidthThreshold = "sliderVisibilityWidthThreshold"
    public static let alwaysSinglePageForCover = "alwaysSinglePageForCover"
    public static let defaultViewMode = "defaultViewMode" // "auto" | "single" | "spread"
    public static let slideshowInterval = "slideshowInterval"
    public static let slideshowEnabled = "slideshowEnabled"
    public static let thumbnailStripVisible = "thumbnailStripVisible"
    public static let pageTransitionEnabled = "pageTransitionEnabled"
    public static let spreadPairOffset = "spreadPairOffset" // 見開きの左右を補正 (0 or 1)
    // ウィンドウフレーム永続化
    public static let restoreWindowFrameEnabled = "restoreWindowFrameEnabled"
    public static let savedWindowFrameString = "savedWindowFrameString"
    // 読書履歴
    public static let readingHistoryEnabled = "readingHistoryEnabled"
    public static let readingHistoryData = "readingHistoryData"
    // Preview Extension 向け画像デコード/キャッシュ方針（"noCache" | "deferred" | "immediate"）
    public static let imageDecodeCachePolicy = "imageDecodeCachePolicy"
    // Preview Extension のサムネイルストリップ高さ（CGFloat、既定値 88）
    public static let thumbnailStripHeight = "thumbnailStripHeight"
    // ファイルルーティング設定ペイロード（JSON エンコードされた KeywordSettings）
    public static let routingSettingsData = "routingSettingsData"
    // Finder QuickLook 用キー入力ヘルパー
    public static let isKeyHelperEnabled = "isKeyHelperEnabled"
    public static let keyHelperLastAccessibilityTrusted = "keyHelperLastAccessibilityTrusted"
    public static let keyHelperLastError = "keyHelperLastError"
    public static let keyHelperFinderFallbackEnabled = "keyHelperFinderFallbackEnabled"
    public static let keyHelperIsEventTapInstalled = "keyHelperIsEventTapInstalled"
    public static let keyHelperActiveSessionID = "keyHelperActiveSessionID"
    public static let keyHelperVisibleUntil = "keyHelperVisibleUntil"
    public static let keyHelperLastVisibleAt = "keyHelperLastVisibleAt"
    public static let keyHelperLastHiddenAt = "keyHelperLastHiddenAt"
    public static let keyHelperLastKeyAt = "keyHelperLastKeyAt"
    public static let keyHelperLastKeyCode = "keyHelperLastKeyCode"
    public static let keyHelperLastFrontmostBundleID = "keyHelperLastFrontmostBundleID"
    public static let keyHelperLastDecision = "keyHelperLastDecision"
    public static let keyHelperLastWindowSummary = "keyHelperLastWindowSummary"
    public static let keyHelperLastCommandAt = "keyHelperLastCommandAt"
    public static let keyHelperLastCommand = "keyHelperLastCommand"
    public static let previewLastVisibilityPostAt = "previewLastVisibilityPostAt"
    public static let previewLastVisibilityPostName = "previewLastVisibilityPostName"
    public static let previewLastVisibilitySessionID = "previewLastVisibilitySessionID"
}

public enum CZAppGroup {
    /// App / Extensions の Entitlements に設定された App Group と一致させること
    public static let identifier: String = "group.com.dmng.CoverZip"
}

public enum CZPreviewSessionCommand: String {
    case setRightToLeftReading
    case setLeftToRightReading
    case setViewModeAuto
    case setViewModeSingle
    case setViewModeSpread
    case setSpreadPairOffset
    case setThumbnailStripVisible
    case setPageTransitionEnabled
    case setSlideshowEnabled
    case goToFirstPage
    case goToLastPage
    case goForwardPage   // 読書順で「次」（論理方向）。物理キー→論理コマンド変換は送信側責務
    case goBackwardPage  // 読書順で「前」（論理方向）。受信側で isRightToLeftReading による反転は不要
    case jumpRelativePages  // intValue に相対量（正=前進、負=後退）
}

public enum CZPreviewSessionCommandUserInfoKeys {
    public static let command = "command"
    public static let commandID = "commandID"
    public static let boolValue = "boolValue"
    public static let intValue = "intValue"
}

/// Preview Extension の可視状態通知に載せる UserInfo キー。
public enum CZPreviewVisibilityUserInfoKeys {
    public static let sessionID = "sessionID"
    public static let timestamp = "timestamp"
}

public enum CZPreviewContextMenuEntry: Equatable {
    case action(CZPreviewSessionCommand)
    case separator
}

public enum CZPreviewContextMenuLayout {
    public static let entries: [CZPreviewContextMenuEntry] = [
        .action(.setRightToLeftReading),
        .action(.setLeftToRightReading),
        .separator,
        .action(.setViewModeAuto),
        .action(.setViewModeSingle),
        .action(.setViewModeSpread),
        .separator,
        .action(.setSpreadPairOffset),
        .action(.setThumbnailStripVisible),
        .separator,
        .action(.setPageTransitionEnabled),
        .action(.setSlideshowEnabled),
    ]

    public static func title(for command: CZPreviewSessionCommand) -> String {
        switch command {
        case .setRightToLeftReading:
            return CZLocalized.string("context.menu.reading.rtl", defaultValue: "Right to Left")
        case .setLeftToRightReading:
            return CZLocalized.string("context.menu.reading.ltr", defaultValue: "Left to Right")
        case .setViewModeAuto:
            return CZLocalized.string("context.menu.view.auto", defaultValue: "Auto")
        case .setViewModeSingle:
            return CZLocalized.string("context.menu.view.single", defaultValue: "Single Page")
        case .setViewModeSpread:
            return CZLocalized.string("context.menu.view.spread", defaultValue: "Spread")
        case .setSpreadPairOffset:
            return CZLocalized.string("context.menu.spread.offset", defaultValue: "Adjust Spread Pairing")
        case .setThumbnailStripVisible:
            return CZLocalized.string("context.menu.thumbnail.visible", defaultValue: "Show Thumbnail List")
        case .setPageTransitionEnabled:
            return CZLocalized.string("context.menu.page_transition.enabled", defaultValue: "Page Transition Animation")
        case .setSlideshowEnabled:
            return CZLocalized.string("context.menu.slideshow.enabled", defaultValue: "Slideshow")
        case .goToFirstPage:
            return CZLocalized.string("context.menu.page.first", defaultValue: "First Page")
        case .goToLastPage:
            return CZLocalized.string("context.menu.page.last", defaultValue: "Last Page")
        case .goForwardPage:
            return CZLocalized.string("context.menu.page.forward", defaultValue: "Next Page")
        case .goBackwardPage:
            return CZLocalized.string("context.menu.page.backward", defaultValue: "Previous Page")
        case .jumpRelativePages:
            return CZLocalized.string("context.menu.page.jump", defaultValue: "Jump Pages")
        }
    }

    public static func symbolName(for command: CZPreviewSessionCommand) -> String {
        CZMenuSymbols.previewCommandSymbolName(for: command)
    }
}

public enum CZMenuSymbols {
    public static let fileOpen = "folder"
    public static let fileOpenInternal = "eye"

    public static func previewCommandSymbolName(for command: CZPreviewSessionCommand) -> String {
        switch command {
        case .setRightToLeftReading:
            return "text.alignright"
        case .setLeftToRightReading:
            return "text.alignleft"
        case .setViewModeAuto:
            return "sparkles"
        case .setViewModeSingle:
            return "rectangle"
        case .setViewModeSpread:
            return "rectangle.split.2x1"
        case .setSpreadPairOffset:
            return "arrow.left.arrow.right"
        case .setThumbnailStripVisible:
            return "rectangle.grid.1x2"
        case .setPageTransitionEnabled:
            return "rectangle.on.rectangle"
        case .setSlideshowEnabled:
            return "play.circle"
        case .goToFirstPage:
            return "backward.end"
        case .goToLastPage:
            return "forward.end"
        case .goForwardPage:
            return "chevron.right"
        case .goBackwardPage:
            return "chevron.left"
        case .jumpRelativePages:
            return "arrow.left.arrow.right.square"
        }
    }
}

#if canImport(AppKit)
public enum CZPreviewContextMenuFactory {
    public typealias ShortcutDefinition = (keyEquivalent: String, modifierMask: NSEvent.ModifierFlags)

    public static func makeMenu(
        target: AnyObject,
        selectorForCommand: (CZPreviewSessionCommand) -> Selector?,
        stateForCommand: (CZPreviewSessionCommand) -> NSControl.StateValue,
        shortcutForCommand: (CZPreviewSessionCommand) -> ShortcutDefinition? = { _ in nil }
    ) -> NSMenu {
        let menu = NSMenu()

        for entry in CZPreviewContextMenuLayout.entries {
            switch entry {
            case .separator:
                menu.addItem(NSMenuItem.separator())
            case .action(let command):
                guard let selector = selectorForCommand(command) else { continue }
                let shortcut = shortcutForCommand(command)
                let item = NSMenuItem(
                    title: CZPreviewContextMenuLayout.title(for: command),
                    action: selector,
                    keyEquivalent: shortcut?.keyEquivalent ?? ""
                )
                item.keyEquivalentModifierMask = shortcut?.modifierMask ?? []
                item.target = target
                item.state = stateForCommand(command)
                if let image = NSImage(
                    systemSymbolName: CZPreviewContextMenuLayout.symbolName(for: command),
                    accessibilityDescription: item.title
                ) {
                    image.isTemplate = true
                    image.size = NSSize(width: 14, height: 14)
                    item.image = image
                }
                menu.addItem(item)
            }
        }

        return menu
    }
}
#endif

// App と Extensions 間で設定を同期するための分散通知
public enum CZDistributedNotifications {
    // App 側設定が変更され、Extensions 側へ反映すべきときに送信
    public static let settingsChanged = Notification.Name("com.dmng.CoverZip.settingsChanged")
    // Preview Extension のスライダー操作完了時に送信（キーボードフォーカス復帰用）
    public static let sliderOperationCompleted = Notification.Name("com.dmng.CoverZip.sliderOperationCompleted")
    // App 側内蔵ビューアのメニュー操作を Preview Extension セッション状態へ反映するときに送信
    public static let previewSessionCommand = Notification.Name("com.dmng.CoverZip.previewSessionCommand")
    // Preview Extension がセッションコマンドを処理したことをヘルパーへ伝える
    public static let previewSessionCommandHandled = Notification.Name("com.dmng.CoverZip.previewSessionCommandHandled")
    // Finder QuickLook 内で CoverZip Preview Extension が表示中であることをヘルパーへ伝える
    public static let previewExtensionVisible = Notification.Name("com.dmng.CoverZip.previewExtensionVisible")
    // Finder QuickLook 内の CoverZip Preview Extension が非表示になったことをヘルパーへ伝える
    public static let previewExtensionHidden = Notification.Name("com.dmng.CoverZip.previewExtensionHidden")
    // 起動中のキー入力ヘルパーへ終了を依頼する
    public static let keyHelperQuitRequested = Notification.Name("com.dmng.CoverZip.keyHelperQuitRequested")
}

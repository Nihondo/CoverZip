//
//  InternalViewer.swift
//  CoverZip
//
//  内蔵ビューアとしてQuick Lookパネルを用いてZIPを表示する薄いラッパー
//

import AppKit
import Foundation

final class InternalViewer: NSObject {
    static let shared = InternalViewer()
    

    // 公開API: 内蔵ビューアでZIPを表示（QLPreviewInputDriver に委譲）
    func show(url: URL) {
        // アプリを前面に
        NSApp.activate(ignoringOtherApps: true)
        // 右クリックのメニューをアプリ側から供給
        QLPreviewInputDriver.contextMenuProvider = { [weak self] in
            guard let self else { return NSMenu() }
            return self.makeContextMenu()
        }
        // 正式経路: 入力ドライバの単体ウィンドウを開く
        QLPreviewInputDriver.openQuickLookWindow(url: url)
    }
    // 共有UserDefaults（App Group 統一）
    func sharedDefaults() -> UserDefaults { UserDefaults(suiteName: CZAppGroup.identifier) ?? .standard }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        // 読み方向
        let isRTL = sharedDefaults().object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool ?? true
        let rightToLeftItem = NSMenuItem(title: "右綴じ", action: #selector(setRightToLeft(_:)), keyEquivalent: "")
        rightToLeftItem.target = self
        rightToLeftItem.state = isRTL ? .on : .off
        menu.addItem(rightToLeftItem)

        let leftToRightItem = NSMenuItem(title: "左綴じ", action: #selector(setLeftToRight(_:)), keyEquivalent: "")
        leftToRightItem.target = self
        leftToRightItem.state = !isRTL ? .on : .off
        menu.addItem(leftToRightItem)

        menu.addItem(NSMenuItem.separator())

        // 表示モード
        let currentMode = sharedDefaults().string(forKey: CZSettingsKeys.defaultViewMode) ?? "auto"
        let autoModeItem = NSMenuItem(title: "自動", action: #selector(setViewModeAuto(_:)), keyEquivalent: "")
        autoModeItem.target = self
        autoModeItem.state = currentMode == "auto" ? .on : .off
        menu.addItem(autoModeItem)

        let singleModeItem = NSMenuItem(title: "単ページ", action: #selector(setViewModeSingle(_:)), keyEquivalent: "")
        singleModeItem.target = self
        singleModeItem.state = currentMode == "single" ? .on : .off
        menu.addItem(singleModeItem)

        let spreadModeItem = NSMenuItem(title: "見開き", action: #selector(setViewModeSpread(_:)), keyEquivalent: "")
        spreadModeItem.target = self
        spreadModeItem.state = currentMode == "spread" ? .on : .off
        menu.addItem(spreadModeItem)

        menu.addItem(NSMenuItem.separator())

        // 見開きの左右を補正
        let currentOffset = sharedDefaults().object(forKey: CZSettingsKeys.spreadPairOffset) as? Int ?? 0
        let spreadOffsetItem = NSMenuItem(title: "見開きの左右を補正", action: #selector(toggleSpreadPairOffset(_:)), keyEquivalent: "")
        spreadOffsetItem.target = self
        spreadOffsetItem.state = currentOffset == 1 ? .on : .off
        menu.addItem(spreadOffsetItem)

        menu.addItem(NSMenuItem.separator())

        // ページ送りアニメ
        let transitionEnabled = sharedDefaults().object(forKey: CZSettingsKeys.pageTransitionEnabled) as? Bool ?? true
        let transitionItem = NSMenuItem(title: "ページ送りアニメ", action: #selector(toggleTransition(_:)), keyEquivalent: "")
        transitionItem.target = self
        transitionItem.state = transitionEnabled ? .on : .off
        menu.addItem(transitionItem)

        // スライドショー
        let slideshowItem = NSMenuItem(title: "スライドショー", action: #selector(toggleSlideshow(_:)), keyEquivalent: "")
        slideshowItem.target = self
        // 状態はプレイヤの状態に依存するためオフで開始
        slideshowItem.state = .off
        menu.addItem(slideshowItem)

        return menu
    }

    // MARK: Actions (App側)
    @objc func setRightToLeft(_ sender: NSMenuItem) {
        sharedDefaults().set(true, forKey: CZSettingsKeys.isRightToLeftReading)
        sender.state = .on
        (sender.menu?.item(withTitle: "左綴じ"))?.state = .off
        // 反映は拡張側に任せる（Shared Defaults参照）
        DistributedNotificationCenter.default().post(name: CZDistributedNotifications.settingsChanged, object: nil)
    }

    @objc func setLeftToRight(_ sender: NSMenuItem) {
        sharedDefaults().set(false, forKey: CZSettingsKeys.isRightToLeftReading)
        sender.state = .on
        (sender.menu?.item(withTitle: "右綴じ"))?.state = .off
        DistributedNotificationCenter.default().post(name: CZDistributedNotifications.settingsChanged, object: nil)
    }

    @objc func setViewModeAuto(_ sender: NSMenuItem) {
        sharedDefaults().set("auto", forKey: CZSettingsKeys.defaultViewMode)
        updateModeStates(sender)
        DistributedNotificationCenter.default().post(name: CZDistributedNotifications.settingsChanged, object: nil)
    }
    @objc func setViewModeSingle(_ sender: NSMenuItem) {
        sharedDefaults().set("single", forKey: CZSettingsKeys.defaultViewMode)
        updateModeStates(sender)
        DistributedNotificationCenter.default().post(name: CZDistributedNotifications.settingsChanged, object: nil)
    }
    @objc func setViewModeSpread(_ sender: NSMenuItem) {
        sharedDefaults().set("spread", forKey: CZSettingsKeys.defaultViewMode)
        updateModeStates(sender)
        DistributedNotificationCenter.default().post(name: CZDistributedNotifications.settingsChanged, object: nil)
    }
    private func updateModeStates(_ sender: NSMenuItem) {
        for t in ["自動","単ページ","見開き"] { sender.menu?.item(withTitle: t)?.state = .off }
        sender.state = .on
    }

    @objc func toggleTransition(_ sender: NSMenuItem) {
        let cur = sharedDefaults().object(forKey: CZSettingsKeys.pageTransitionEnabled) as? Bool ?? true
        let next = !cur
        sharedDefaults().set(next, forKey: CZSettingsKeys.pageTransitionEnabled)
        sender.state = next ? .on : .off
        DistributedNotificationCenter.default().post(name: CZDistributedNotifications.settingsChanged, object: nil)
    }

    @objc func toggleSlideshow(_ sender: NSMenuItem) {
        // この場では状態のみ表示を切替。実動作は拡張側/プレビュー側で。
        sender.state = (sender.state == .on) ? .off : .on
    }

    @objc func toggleSpreadPairOffset(_ sender: NSMenuItem) {
        let current = sharedDefaults().object(forKey: CZSettingsKeys.spreadPairOffset) as? Int ?? 0
        let next = 1 - current  // 0 ↔ 1 をトグル
        sharedDefaults().set(next, forKey: CZSettingsKeys.spreadPairOffset)
        sender.state = next == 1 ? .on : .off
        // Preview Extension側への反映通知
        DistributedNotificationCenter.default().post(name: CZDistributedNotifications.settingsChanged, object: nil)
    }


    // 旧QLPreviewPanel連携は廃止（QLPreviewInputDriverが内部でフォールバックを持つ）
}

// MARK: - Helpers
private extension InternalViewer { }

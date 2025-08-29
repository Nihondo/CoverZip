//
//  InternalViewer.swift
//  CoverZip
//
//  内蔵ビューアとしてQuick Lookパネルを用いてZIPを表示する薄いラッパー
//

import AppKit
import ApplicationServices
import QuickLook
import QuickLookUI
import Foundation

final class InternalViewer: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = InternalViewer()

    private var currentURL: URL?
    // 埋め込みウィンドウ管理
    private var embeddedWindows: [NSWindow] = []
    private var windowKeyMonitors: [Int: [Any]] = [:]
    private static var didPromptAX = false

    // 公開API: 内蔵ビューアでZIPを表示（QLPreviewViewを埋め込み）
    func show(url: URL) {
    // アプリを前面に
    NSApp.activate(ignoringOtherApps: true)

        // アクセシビリティ権限を事前チェック（必要ならプロンプト）
        if !AXIsProcessTrusted() && !Self.didPromptAX {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            Self.didPromptAX = true
            NSLog("[EmbeddedQL] Requested Accessibility permission for CGEvent posting")
        }

        // ウィンドウ生成
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
    window.title = url.lastPathComponent
        window.center()

    guard let content = window.contentView else { return }
        // QLPreviewView を生成
        let pv = QLPreviewView(frame: .zero, style: .normal)
        if pv == nil {
            // フォールバック: 共有パネル
            currentURL = url
            if let panel = QLPreviewPanel.shared() {
                panel.dataSource = self
                panel.delegate = self
                panel.makeKeyAndOrderFront(nil)
                panel.reloadData()
                return
            } else {
                _ = NSWorkspace.shared.open(url)
                return
            }
        }
        guard let previewView = pv else { return }

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.shouldCloseWithWindow = true
        previewView.autoresizesSubviews = true
        content.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: content.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        previewView.previewItem = url as NSURL
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(previewView)

        embeddedWindows.append(window)

    // コンテキストメニューは拡張側で右クリック/Control-クリックをフックして表示する

        // 左右キーでプレビュー内クリックを合成（拡張側のクリック遷移を呼ぶ）
        let addMonitors: () -> Void = { [weak self, weak window, weak previewView] in
            guard let self, let window, let previewView else { return }
            var monitors: [Any] = []
            if let m1 = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak window, weak previewView] event -> NSEvent? in
                guard let win = window, win.isKeyWindow, let pv = previewView else { return event }
                switch Int(event.keyCode) {
                case 123: // ← 左半分
                    NSLog("[EmbeddedQL] keyDown ← (code=%d, isKey=%d)", Int(event.keyCode), win.isKeyWindow ? 1 : 0)
                    Self.synthesizeClick(in: pv, window: win, onLeftHalf: true)
                    return nil
                case 124: // → 右半分
                    NSLog("[EmbeddedQL] keyDown → (code=%d, isKey=%d)", Int(event.keyCode), win.isKeyWindow ? 1 : 0)
                    Self.synthesizeClick(in: pv, window: win, onLeftHalf: false)
                    return nil
                default:
                    return event
                }
            }) { monitors.append(m1) }

            if let m2 = NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: { event -> NSEvent? in
                let code = Int(event.keyCode)
                if code == 123 || code == 124 { return nil }
                return event
            }) { monitors.append(m2) }

            self.windowKeyMonitors[window.windowNumber] = monitors
        }

        addMonitors()

        // ウィンドウクローズ時にクリーンアップ
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] note in
            guard let self, let win = note.object as? NSWindow else { return }
            if let monitors = self.windowKeyMonitors.removeValue(forKey: win.windowNumber) {
                for m in monitors { NSEvent.removeMonitor(m) }
            }
            self.embeddedWindows.removeAll { $0 == win }
        }
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
    }

    @objc func setLeftToRight(_ sender: NSMenuItem) {
        sharedDefaults().set(false, forKey: CZSettingsKeys.isRightToLeftReading)
        sender.state = .on
        (sender.menu?.item(withTitle: "右綴じ"))?.state = .off
    }

    @objc func setViewModeAuto(_ sender: NSMenuItem) {
        sharedDefaults().set("auto", forKey: CZSettingsKeys.defaultViewMode)
        updateModeStates(sender)
    }
    @objc func setViewModeSingle(_ sender: NSMenuItem) {
        sharedDefaults().set("single", forKey: CZSettingsKeys.defaultViewMode)
        updateModeStates(sender)
    }
    @objc func setViewModeSpread(_ sender: NSMenuItem) {
        sharedDefaults().set("spread", forKey: CZSettingsKeys.defaultViewMode)
        updateModeStates(sender)
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
    }

    @objc func toggleSlideshow(_ sender: NSMenuItem) {
        // この場では状態のみ表示を切替。実動作は拡張側/プレビュー側で。
        sender.state = (sender.state == .on) ? .off : .on
    }


    // MARK: - QLPreviewPanelDataSource
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return currentURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        // 既存API互換のため残すが、現在は未使用
        return currentURL as NSURL?
    }

    // MARK: - QLPreviewPanelDelegate (必要に応じて拡張)
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // ここで独自のキーハンドリング等を行いたい場合に拡張
        return false
    }
}

// MARK: - Helpers
private extension InternalViewer {
    static func synthesizeClick(in previewView: QLPreviewView, window: NSWindow, onLeftHalf: Bool) {
        let bounds = previewView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        let x = onLeftHalf ? bounds.width * 0.25 : bounds.width * 0.75
        let y = bounds.height * 0.5
        let pointInView = NSPoint(x: x, y: y)
        let pointInWindow = previewView.convert(pointInView, to: nil)

    NSLog("[EmbeddedQL] synthesizeClick side=%@ view=(%.1f,%.1f) window=(%.1f,%.1f) bounds=%@", onLeftHalf ? "left" : "right", x, y, pointInWindow.x, pointInWindow.y, NSStringFromRect(bounds))

        func post(_ type: NSEvent.EventType) {
            if let ev = NSEvent.mouseEvent(
                with: type,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1.0
            ) {
                NSLog("[EmbeddedQL] postEvent %@ at window=(%.1f,%.1f)", String(describing: type), pointInWindow.x, pointInWindow.y)
                NSApp.postEvent(ev, atStart: false)
            }
        }
        post(.leftMouseDown)
        post(.leftMouseUp)

        // フォールバック: CGEvent（グローバル）
        guard AXIsProcessTrusted() else {
            NSLog("[EmbeddedQL] Accessibility not trusted; skip CGEvent posting")
            return
        }
        let screenPoint = window.convertPoint(toScreen: pointInWindow)
        let totalMaxY = NSScreen.screens.map { $0.frame.maxY }.max() ?? screenPoint.y
        let cgPoint = CGPoint(x: screenPoint.x, y: totalMaxY - screenPoint.y)
        NSLog("[EmbeddedQL] CGEvent click at screen=(%.1f,%.1f) (from window=(%.1f,%.1f))", cgPoint.x, cgPoint.y, screenPoint.x, screenPoint.y)
        if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cgPoint, mouseButton: .left),
           let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cgPoint, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            NSLog("[EmbeddedQL] CGEvent posted (down/up)")
        } else {
            NSLog("[EmbeddedQL] CGEvent create failed")
        }
    }
}

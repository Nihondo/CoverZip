//
//  QLPreviewInputDriver.swift
//  CoverZip
//
//  Quick Look 埋め込みの入力ドライバ（正式実装）。
//  - First Responder 専用のフォワーダビューで左右キーを受け取り、
//    プレビュー領域左右半分へのクリック（ダウン/アップ）を合成してページ送りを駆動
//  - イベントモニタは任意（デバッグ/フォールバック用途）。
//  - ウィンドウクローズは OS の標準挙動に委ね、独自破棄は行わない。
//

import AppKit
import ApplicationServices
import QuickLook
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look 埋め込みの入力制御を提供するユーティリティ（正式版）
enum QLPreviewInputDriver {
    /// テスト用ウィンドウを保持（早期解放を防ぐ）
    private static var retainedWindows: [NSWindow] = []
    /// ウィンドウごとのローカルモニタ保持
    private static var keyMonitors: [Int: [Any]] = [:]

    /// オープンパネルを出して ZIP を選択し、最小構成の QLPreviewView ウィンドウを開く
    /// - Note: 開発メニューや動作確認用のユーティリティ。
    static func presentAndOpen() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.zip]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            openQuickLookWindow(url: url)
        }
    }

    /// 指定 URL を QLPreviewView 単体で表示するウィンドウを開く
    /// - Parameters:
    ///   - url: 表示する ZIP の URL
    ///   - enableKeyMonitors: ローカルイベントモニタを有効化（デバッグ用途）
    static func openQuickLookWindow(url: URL, enableKeyMonitors: Bool = false) {
        DispatchQueue.main.async {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Preview – " + url.lastPathComponent
            window.center()

            guard let content = window.contentView else { return }
            guard let previewView = QLPreviewView(frame: .zero, style: .normal) else {
                // 生成失敗時は共有パネルへフォールバック
                if let panel = QLPreviewPanel.shared() {
                    panel.dataSource = SimplePanelDataSource(item: url as NSURL)
                    panel.makeKeyAndOrderFront(nil)
                    panel.reloadData()
                }
                return
            }

            previewView.translatesAutoresizingMaskIntoConstraints = false
            previewView.shouldCloseWithWindow = true
            content.addSubview(previewView)
            NSLayoutConstraint.activate([
                previewView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                previewView.topAnchor.constraint(equalTo: content.topAnchor),
                previewView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
            previewView.previewItem = url as NSURL

            let forwarderRef = addKeyForwarder(window: window, previewView: previewView)
            if enableKeyMonitors {
                addKeyMonitors(window: window, previewView: previewView)
            }

            // クローズ時に参照/モニタを解放
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { note in
                // ローカルモニタは現状未使用だが、将来のために解除ロジックは残す
                if let monitors = keyMonitors.removeValue(forKey: window.windowNumber) { for m in monitors { NSEvent.removeMonitor(m) } }
                retainedWindows.removeAll { $0 == window }
            }

            retainedWindows.append(window)
            window.makeKeyAndOrderFront(nil)
            if let f = forwarderRef {
                // キー化後に改めて First Responder をセット（QL が奪うのを防ぐ）
                DispatchQueue.main.async { window.makeFirstResponder(f) }
                // ウィンドウがキーになったタイミングで再設定
                let obs = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                    window.makeFirstResponder(f)
                }
                // ウィンドウクローズでオブザーバ解除
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                    NotificationCenter.default.removeObserver(obs)
                }
            }
        }
    }

    /// 既存ウィンドウに入力フォワーダを取り付ける（埋め込み用）
    /// - Note: 内蔵ビューアの埋め込み `QLPreviewView` に対して矢印キー→クリック合成を提供する。
    static func attachInputForwarder(to window: NSWindow, previewView: QLPreviewView) {
        guard let forwarder = addKeyForwarder(window: window, previewView: previewView) else { return }
        // キー化後に改めて First Responder をセット（QL が奪うのを防ぐ）
        DispatchQueue.main.async { window.makeFirstResponder(forwarder) }
        let obs = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            window.makeFirstResponder(forwarder)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // 方式1: ローカルモニタ（現在は未使用）
    private static func addKeyMonitors(window: NSWindow, previewView: QLPreviewView) {
        var monitors: [Any] = []
        if let m1 = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak window, weak previewView] event -> NSEvent? in
            guard let win = window, win.isKeyWindow, let pv = previewView else { return event }
            switch Int(event.keyCode) {
            case 123: // ← 左半分
                synthesizeClick(in: pv, window: win, onLeftHalf: true)
                return nil
            case 124: // → 右半分
                synthesizeClick(in: pv, window: win, onLeftHalf: false)
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

        keyMonitors[window.windowNumber] = monitors
    }

    // 方式2: First Responder フォワーダ（推奨）
    private static func addKeyForwarder(window: NSWindow, previewView: QLPreviewView) -> KeyForwardingView? {
        let forwarder = KeyForwardingView { isLeft in
            synthesizeClick(in: previewView, window: window, onLeftHalf: isLeft)
        }
        forwarder.translatesAutoresizingMaskIntoConstraints = false
        forwarder.isHidden = false
        forwarder.wantsLayer = false

        guard let content = window.contentView else { return nil }
        content.addSubview(forwarder, positioned: .above, relativeTo: previewView)
        NSLayoutConstraint.activate([
            forwarder.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            forwarder.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            forwarder.topAnchor.constraint(equalTo: content.topAnchor),
            forwarder.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.initialFirstResponder = forwarder
        return forwarder
    }

    private final class KeyForwardingView: NSView {
        private let handler: (Bool) -> Void
        init(handler: @escaping (Bool) -> Void) { self.handler = handler; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override var acceptsFirstResponder: Bool { true }
        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil } // マウスは下のビューへ通す
        override func keyDown(with event: NSEvent) {
            NSLog("[QLInputDriver] keyDown code=%d flags=%lu", Int(event.keyCode), event.modifierFlags.rawValue)
            switch Int(event.keyCode) {
            case 123: handler(true)  // ← 左半分クリック
            case 124: handler(false) // → 右半分クリック
            default: super.keyDown(with: event)
            }
        }
    }

    private static func synthesizeClick(in previewView: QLPreviewView, window: NSWindow, onLeftHalf: Bool) {
        let bounds = previewView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        let x = onLeftHalf ? bounds.width * 0.25 : bounds.width * 0.75
        let y = bounds.height * 0.5
        let pointInView = NSPoint(x: x, y: y)
        let pointInWindow = previewView.convert(pointInView, to: nil)

        func post(_ type: NSEvent.EventType) {
            guard let ev = NSEvent.mouseEvent(
                with: type,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1.0
            ) else { return }
            NSApp.postEvent(ev, atStart: false)
        }
        post(.leftMouseDown)
        post(.leftMouseUp)

        // フォールバック: CGEvent（アクセシビリティ権限がある場合のみ）
        if AXIsProcessTrusted() {
            let screenPoint = window.convertPoint(toScreen: pointInWindow)
            let totalMaxY = NSScreen.screens.map { $0.frame.maxY }.max() ?? screenPoint.y
            let cgPoint = CGPoint(x: screenPoint.x, y: totalMaxY - screenPoint.y)
            if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cgPoint, mouseButton: .left),
               let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cgPoint, mouseButton: .left) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }
}

/// 共有パネル用の最小データソース
private final class SimplePanelDataSource: NSObject, QLPreviewPanelDataSource {
    private let item: QLPreviewItem
    init(item: QLPreviewItem) { self.item = item }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { item }
}

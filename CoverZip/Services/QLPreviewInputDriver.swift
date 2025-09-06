//
//  QLPreviewInputDriver.swift
//  CoverZip
//
//  Quick Look 埋め込みの入力ドライバ（正式実装）。
//  - First Responder 専用のフォワーダビューで左右キーを受け取り、
//    プレビュー領域左右半分へのクリック（ダウン/アップ）を合成してページ送りを駆動
//  - 入力はフォワーダビュー経由に統一（ローカルイベントモニタは廃止）。
//  - クリック注入は CGEvent を使用（アクセシビリティ権限が必要）。
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
    // ローカルイベントモニタは廃止（フォワーダ方式に一本化）
    private static var didPromptAX: Bool = false
    /// コンテキストメニュー供給（アプリ側で設定）
    static var contextMenuProvider: (() -> NSMenu)?
    
    /// アクセシビリティ権限を確認し、必要なら一度だけプロンプトを表示
    /// - Returns: 権限が有効なら true
    @discardableResult
    private static func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !didPromptAX {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let options = [key: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            didPromptAX = true
            NSLog("[QLInputDriver] Requested Accessibility permission for CGEvent posting")
        }
        return AXIsProcessTrusted()
    }

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
    /// - Parameter url: 表示する ZIP の URL
    static func openQuickLookWindow(url: URL) {
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

            // クローズ時に参照を解放
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { note in
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

    // ローカルイベントモニタ方式は削除（安定構成へ統一）

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
        // 左クリックはプレビューへ通し、右クリック/Control-クリックは自分で受ける
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let ev = NSApp.currentEvent else { return nil }
            if ev.type == .rightMouseDown { return self }
            if ev.type == .leftMouseDown && ev.modifierFlags.contains(.control) { return self }
            return nil
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let win = self.window { DispatchQueue.main.async { win.makeFirstResponder(self) } }
        }
        override func keyDown(with event: NSEvent) {
            NSLog("[QLInputDriver] keyDown code=%d flags=%lu", Int(event.keyCode), event.modifierFlags.rawValue)
            switch Int(event.keyCode) {
            case 123: handler(true)  // ← 左半分クリック
            case 124: handler(false) // → 右半分クリック
            default: super.keyDown(with: event)
            }
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            return QLPreviewInputDriver.contextMenuProvider?()
        }
    }

    private static func synthesizeClick(in previewView: QLPreviewView, window: NSWindow, onLeftHalf: Bool) {
        let bounds = previewView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        let x = onLeftHalf ? bounds.width * 0.25 : bounds.width * 0.75
        let y = bounds.height * 0.5
        let pointInView = NSPoint(x: x, y: y)
        let pointInWindow = previewView.convert(pointInView, to: nil)

        // CGEvent（リモートレイヤ越しに確実にイベントを届ける）
        guard ensureAccessibilityPermission() else {
            NSLog("[QLInputDriver] Cannot synthesize click: Accessibility permission not granted")
            return
        }
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

/// 共有パネル用の最小データソース
private final class SimplePanelDataSource: NSObject, QLPreviewPanelDataSource {
    private let item: QLPreviewItem
    init(item: QLPreviewItem) { self.item = item }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { item }
}

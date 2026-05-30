//
//  QLPreviewInputDriver.swift
//  CoverZip
//
//  Quick Look 埋め込みの入力ドライバ（正式実装）。
//  - First Responder 専用フォワーダビューで左右キーを受け取り、
//    分散コマンド経由でページ遷移を駆動
//  - 入力はフォワーダビュー経由に統一（ローカルイベントモニタは廃止）。
//  - ウィンドウクローズは OS の標準挙動に委ね、独自破棄は行わない。
//

import AppKit
import QuickLook
import QuickLookUI

/// 弱参照ラッパー
private class WeakRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// Quick Look 埋め込みの入力制御を提供するユーティリティ（正式版）
enum QLPreviewInputDriver {
    /// ビューアウィンドウの開閉状態が変化したときに `NotificationCenter.default` へ投稿する通知名。
    /// userInfo なし。`hasOpenViewerWindow` で現在の状態を取得できる。
    static let viewerWindowStateChanged = Notification.Name("com.dmng.CoverZip.viewerWindowStateChanged")

    /// 現在ビューアウィンドウが1つ以上開いているかどうか
    static var hasOpenViewerWindow: Bool { !retainedWindows.isEmpty }

    /// テスト用ウィンドウを保持（早期解放を防ぐ）
    private static var retainedWindows: [NSWindow] = []
    /// KeyForwardingView の弱参照を保持（フォーカス復帰用）
    private static var keyForwarders: [WeakRef<KeyForwardingView>] = []
    /// コンテキストメニュー供給（アプリ側で設定）
    static var contextMenuProvider: (() -> NSMenu)?
    /// 共有パネル用データソースを強参照で保持（QLPreviewPanel.dataSourceはunowned）
    private static var retainedPanelDataSource: SimplePanelDataSource?

    // MARK: - キーボードフォーカス管理

    /// KeyForwardingView にキーボードフォーカスを復帰させる
    private static func restoreKeyboardFocus() {
        // 無効な弱参照を削除
        keyForwarders.removeAll { $0.value == nil }

        // 有効なフォワーダへフォーカスを復帰
        for weakRef in keyForwarders {
            if let forwarder = weakRef.value,
               let window = forwarder.window {
                window.makeFirstResponder(forwarder)
                NSLog("[QLInputDriver] Restored keyboard focus to KeyForwardingView")
                break
            }
        }
    }

    /// スライダー操作完了通知の監視を開始
    private static func setupSliderNotificationObserver() {
        DistributedNotificationCenter.default.addObserver(
            forName: CZDistributedNotifications.sliderOperationCompleted,
            object: nil,
            queue: .main
        ) { _ in
            NSLog("[QLInputDriver] Received slider operation completed notification")
            // 少し遅延を入れてフォーカス復帰（スライダー処理完了を待つ）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                restoreKeyboardFocus()
            }
        }
    }

    // MARK: - ウィンドウフレーム管理

    /// ウィンドウフレーム復元が有効かどうか
    private static func isRestoreWindowFrameEnabled() -> Bool {
        return CZUserDefaults.shared.object(forKey: CZSettingsKeys.restoreWindowFrameEnabled) as? Bool ?? true
    }

    /// 保存されたウィンドウフレームを読み込み
    private static func loadSavedWindowFrame() -> NSRect? {
        guard isRestoreWindowFrameEnabled(),
              let frameString = CZUserDefaults.shared.string(forKey: CZSettingsKeys.savedWindowFrameString) else {
            return nil
        }
        return NSRectFromString(frameString)
    }

    /// ウィンドウフレームを保存
    private static func saveWindowFrame(_ frame: NSRect) {
        guard isRestoreWindowFrameEnabled() else { return }
        CZUserDefaults.shared.set(NSStringFromRect(frame), forKey: CZSettingsKeys.savedWindowFrameString)
        NSLog("[QLInputDriver] Saved window frame: %@", NSStringFromRect(frame))
    }

    /// 適切な初期ウィンドウサイズを計算
    private static func calculateInitialWindowSize() -> NSSize {
        // 保存されたサイズがあればそれを使用
        if let savedFrame = loadSavedWindowFrame() {
            return savedFrame.size
        }

        // スクリーンサイズの75%程度の大きさで開く
        guard let screen = NSScreen.main else {
            return NSSize(width: 900, height: 650) // フォールバック
        }

        let visibleFrame = screen.visibleFrame
        let width = visibleFrame.width * 0.75
        let height = visibleFrame.height * 0.75

        // 最小サイズ制限
        let minWidth: CGFloat = 600
        let minHeight: CGFloat = 400

        return NSSize(
            width: max(width, minWidth),
            height: max(height, minHeight)
        )
    }
    
    /// 指定 URL を QLPreviewView 単体で表示するウィンドウを開く
    /// - Parameter url: 表示する ZIP の URL
    static func openQuickLookWindow(url: URL) {
        DispatchQueue.main.async {
            // 保存されたフレームまたは計算された初期サイズを使用
            let initialSize = calculateInitialWindowSize()
            let initialFrame: NSRect

            if let savedFrame = loadSavedWindowFrame() {
                // 保存されたフレーム位置も復元
                initialFrame = savedFrame
            } else {
                // 新規の場合は中央配置で初期サイズを使用
                initialFrame = NSRect(origin: .zero, size: initialSize)
            }

            let window = NSWindow(
                contentRect: initialFrame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = url.lastPathComponent
            window.representedURL = url
            window.tabbingMode = .disallowed
            window.collectionBehavior = [.managed, .participatesInCycle]

            // 保存されたフレームがない場合のみ中央配置
            if loadSavedWindowFrame() == nil {
                window.center()
            }

            // スライダー操作完了通知の監視を開始（初回のみ）
            if keyForwarders.isEmpty {
                setupSliderNotificationObserver()
            }

            guard let content = window.contentView else { return }
            guard let previewView = QLPreviewView(frame: .zero, style: .normal) else {
                // 生成失敗時は共有パネルへフォールバック
                if let panel = QLPreviewPanel.shared() {
                    let dataSource = SimplePanelDataSource(item: url as NSURL)
                    retainedPanelDataSource = dataSource
                    panel.dataSource = dataSource
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

            let forwarderRef = addKeyForwarder(window: window)

            // ウィンドウフレーム変更の監視（リサイズ・移動時に保存）
            let frameObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { _ in
                saveWindowFrame(window.frame)
            }

            let moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { _ in
                saveWindowFrame(window.frame)
            }

            // クローズ時に参照を解放＋オブザーバ解除＋最終フレーム保存
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { note in
                // 最終フレームを保存
                saveWindowFrame(window.frame)
                // オブザーバ解除
                NotificationCenter.default.removeObserver(frameObserver)
                NotificationCenter.default.removeObserver(moveObserver)
                // 参照解放
                retainedWindows.removeAll { $0 == window }
                NotificationCenter.default.post(name: viewerWindowStateChanged, object: nil)
            }

            retainedWindows.append(window)
            NotificationCenter.default.post(name: viewerWindowStateChanged, object: nil)
            window.makeKeyAndOrderFront(nil)
            if let f = forwarderRef {
                // キー化後に改めて First Responder を設定（QL に奪われるのを防ぐ）
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
    /// - Note: 矢印キー入力を分散コマンドへ変換する。
    static func attachInputForwarder(to window: NSWindow) {
        guard let forwarder = addKeyForwarder(window: window) else { return }
        // キー化後に改めて First Responder を設定（QL に奪われるのを防ぐ）
        DispatchQueue.main.async { window.makeFirstResponder(forwarder) }
        let obs = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            window.makeFirstResponder(forwarder)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // ローカルイベントモニタ方式は削除（安定構成へ統一）

    // 方式2: First Responder フォワーダ方式（推奨）
    private static func addKeyForwarder(window: NSWindow) -> KeyForwardingView? {
        let forwarder = KeyForwardingView()
        forwarder.translatesAutoresizingMaskIntoConstraints = false
        forwarder.isHidden = false
        forwarder.wantsLayer = false

        guard let content = window.contentView else { return nil }
        content.addSubview(forwarder)
        NSLayoutConstraint.activate([
            forwarder.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            forwarder.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            forwarder.topAnchor.constraint(equalTo: content.topAnchor),
            forwarder.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.initialFirstResponder = forwarder

        // KeyForwardingView の弱参照を登録
        keyForwarders.append(WeakRef(forwarder))
        NSLog("[QLInputDriver] Registered KeyForwardingView for focus management")

        return forwarder
    }

    private final class KeyForwardingView: NSView {
        required init?(coder: NSCoder) { nil }
        init() { super.init(frame: .zero) }
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
            let isBarePreviewCommand = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            switch Int(event.keyCode) {
            case 29 where isBarePreviewCommand: PreviewSessionCommandDispatcher.post(command: .setViewModeAuto)    // 0
            case 18 where isBarePreviewCommand: PreviewSessionCommandDispatcher.post(command: .setViewModeSingle)  // 1
            case 19 where isBarePreviewCommand: PreviewSessionCommandDispatcher.post(command: .setViewModeSpread)  // 2
            case 17 where isBarePreviewCommand: PreviewSessionCommandDispatcher.post(command: .setSpreadPairOffset) // T
            case 37 where isBarePreviewCommand: PreviewSessionCommandDispatcher.post(command: .setThumbnailStripVisible) // L
            case 1 where isBarePreviewCommand: PreviewSessionCommandDispatcher.post(command: .setSlideshowEnabled) // S
            case 123, 124: // ← or →
                let isLeft  = (Int(event.keyCode) == 123)
                let isCmd   = event.modifierFlags.contains(.command)
                let isShift = event.modifierFlags.contains(.shift)
                if isCmd {
                    PreviewSessionCommandDispatcher.post(command: isLeft ? .goToLeftArrowEdgePage : .goToRightArrowEdgePage)
                } else if isShift {
                    PreviewSessionCommandDispatcher.post(command: isLeft ? .jumpLeftArrowPages : .jumpRightArrowPages, intValue: 10)
                } else {
                    PreviewSessionCommandDispatcher.post(command: isLeft ? .goLeftArrowPage : .goRightArrowPage)
                }
            case 49:  // Space: 読み方向に応じてページ送り/戻し
                let goForward = !event.modifierFlags.contains(.shift)
                PreviewSessionCommandDispatcher.post(command: goForward ? .goForwardPage : .goBackwardPage)
            case 115: PreviewSessionCommandDispatcher.post(command: .goToFirstPage)               // Home
            case 119: PreviewSessionCommandDispatcher.post(command: .goToLastPage)                // End
            case 116: PreviewSessionCommandDispatcher.post(command: .jumpRelativePages, intValue: -10) // Page Up
            case 121: PreviewSessionCommandDispatcher.post(command: .jumpRelativePages, intValue: +10) // Page Down
            default: super.keyDown(with: event)
            }
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            return QLPreviewInputDriver.contextMenuProvider?()
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

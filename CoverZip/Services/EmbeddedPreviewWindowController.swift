//
//  EmbeddedPreviewWindowController.swift
//  CoverZip
//
//  QLPreviewView を埋め込んだドキュメントウィンドウ
//

import AppKit
import QuickLookUI
import ApplicationServices

final class EmbeddedPreviewWindowController: NSWindowController {
    private let url: URL
    private let previewView: QLPreviewView? = QLPreviewView(frame: .zero, style: .normal)
    private var keyMonitors: [Any] = []

    init(url: URL) {
        self.url = url

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url.lastPathComponent
        window.tabbingMode = .preferred
        window.center()

        super.init(window: window)

        setupContent()
        setupKeyHandling()
        loadPreview()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupContent() {
        guard let content = window?.contentView else { return }
        guard let pv = previewView else { return }
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.shouldCloseWithWindow = true
        pv.autoresizesSubviews = true
        content.addSubview(pv)
        NSLayoutConstraint.activate([
            pv.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pv.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pv.topAnchor.constraint(equalTo: content.topAnchor),
            pv.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func loadPreview() {
    previewView?.previewItem = url as NSURL
    // 可能ならフォーカスをQLビューに移す
    if let pv = previewView { window?.makeFirstResponder(pv) }
    }

    private func setupKeyHandling() {
        // 左右キーでQLPreviewView内の左右半分にクリックを合成（拡張のクリックナビを起動）
        if let km = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event -> NSEvent? in
            guard let self, let win = self.window, win.isKeyWindow else { return event }
            switch Int(event.keyCode) {
            case 123: // ← 左半分をクリック（右綴じでは進む）
        NSLog("[EmbeddedQL] keyDown ← (code=%d, isKey=%d)", Int(event.keyCode), win.isKeyWindow ? 1 : 0)
                self.synthesizeClick(onLeftHalf: true)
                return nil
            case 124: // → 右半分をクリック
        NSLog("[EmbeddedQL] keyDown → (code=%d, isKey=%d)", Int(event.keyCode), win.isKeyWindow ? 1 : 0)
                self.synthesizeClick(onLeftHalf: false)
                return nil
            default:
                return event
            }
        }) { keyMonitors.append(km) }
    }

    private func synthesizeClick(onLeftHalf: Bool) {
    guard let win = window, let pv = previewView else { return }
    let bounds = pv.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }
        let x = onLeftHalf ? bounds.width * 0.25 : bounds.width * 0.75
        let y = bounds.height * 0.5
        let pointInView = NSPoint(x: x, y: y)
    let pointInWindow = pv.convert(pointInView, to: nil)

    NSLog("[EmbeddedQL] synthesizeClick side=%@ view=(%.1f,%.1f) window=(%.1f,%.1f) bounds=%@", onLeftHalf ? "left" : "right", x, y, pointInWindow.x, pointInWindow.y, NSStringFromRect(bounds))

        func post(_ type: NSEvent.EventType) {
            if let ev = NSEvent.mouseEvent(
                with: type,
                location: pointInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: win.windowNumber,
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

        // フォールバック: CGEvent によるグローバルクリック（拡張側へ確実に届けるため）
        guard AXIsProcessTrusted() else {
            NSLog("[EmbeddedQL] Accessibility not trusted; skip CGEvent posting")
            return
        }
        let screenPoint = win.convertPoint(toScreen: pointInWindow)
        // グローバル座標系（原点=左上）への変換
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

    deinit {
        for m in keyMonitors { NSEvent.removeMonitor(m) }
        keyMonitors.removeAll()
    }
}

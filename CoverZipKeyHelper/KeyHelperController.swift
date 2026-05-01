//
//  KeyHelperController.swift
//  CoverZipKeyHelper
//
//  Finder QuickLook 表示中だけカーソルキーをページ送り通知へ変換する
//

import AppKit
import ApplicationServices
import Foundation

/// Finder QuickLook 上の CoverZip Preview Extension に対してキー操作を中継するコントローラ。
final class KeyHelperController: NSObject {
    private let visibilityTimeout: TimeInterval = 2.5
    private let finderFallbackTimeout: TimeInterval = 300
    private let trustedCheckInterval: TimeInterval = 5.0
    private static let spaceKeyCode: Int64 = 49
    private static let escapeKeyCode: Int64 = 53
    private static let wKeyCode: Int64 = 13
    private let allowedFrontmostBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.QuickLookUIService",
        "com.apple.quicklook.ui.helper",
        "com.apple.quicklook.QuickLookUIService"
    ]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeSessionID: String?
    private var visibleUntil: Date?
    private var finderFallbackUntil: Date?
    private var trustedCheckTimer: Timer?
    private var isAccessibilityTrusted = false
    private var didUseFinderFallbackForLastCapture = false
    // Preview Extension から可視通知で受け取った最新の読み方向を保持する。
    // クロスプロセスの UserDefaults はキャッシュにより値が古くなることがあるため、
    // 通知経由で受け取った値を優先して利用する。
    private var cachedIsRightToLeftReading: Bool = true

    override init() {
        super.init()
        NSLog("[CoverZipKeyHelper] started")
        cachedIsRightToLeftReading = readIsRightToLeftReadingFromDefaults()
        setupDistributedNotificationObservers()
        refreshAccessibilityTrust(installIfNeeded: true, promptIfNeeded: isKeyHelperEnabledForRuntime())
        startTrustedCheckTimer()
    }

    deinit {
        NSLog("[CoverZipKeyHelper] deinit")
        teardownEventTap()
        DistributedNotificationCenter.default().removeObserver(self)
        trustedCheckTimer?.invalidate()
    }

    private func setupDistributedNotificationObservers() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(handlePreviewVisible(_:)),
            name: CZDistributedNotifications.previewExtensionVisible,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self,
            selector: #selector(handlePreviewHidden(_:)),
            name: CZDistributedNotifications.previewExtensionHidden,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self,
            selector: #selector(handleQuitRequested(_:)),
            name: CZDistributedNotifications.keyHelperQuitRequested,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        center.addObserver(
            self,
            selector: #selector(handlePreviewSessionCommandHandled(_:)),
            name: CZDistributedNotifications.previewSessionCommandHandled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    private func startTrustedCheckTimer() {
        trustedCheckTimer = Timer(timeInterval: trustedCheckInterval, repeats: true) { [weak self] _ in
            self?.refreshAccessibilityTrust(installIfNeeded: true, promptIfNeeded: false)
        }
        if let trustedCheckTimer {
            RunLoop.main.add(trustedCheckTimer, forMode: .common)
        }
    }

    private func refreshAccessibilityTrust(installIfNeeded: Bool, promptIfNeeded: Bool) {
        let trusted = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded
        ] as CFDictionary)

        if trusted != isAccessibilityTrusted {
            NSLog("[CoverZipKeyHelper] accessibility trusted changed: %d", trusted ? 1 : 0)
        }
        isAccessibilityTrusted = trusted
        CZUserDefaults.shared.set(trusted, forKey: CZSettingsKeys.keyHelperLastAccessibilityTrusted)

        if trusted {
            if installIfNeeded && eventTap == nil {
                installEventTap()
            }
        } else if eventTap != nil {
            teardownEventTap()
        }
    }

    private func installEventTap() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: KeyHelperController.keyEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[CoverZipKeyHelper] CGEvent.tapCreate failed")
            CZUserDefaults.shared.set("CGEvent.tapCreate failed", forKey: CZSettingsKeys.keyHelperLastError)
            CZUserDefaults.shared.set(false, forKey: CZSettingsKeys.keyHelperIsEventTapInstalled)
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[CoverZipKeyHelper] event tap installed")
        CZUserDefaults.shared.set(true, forKey: CZSettingsKeys.keyHelperIsEventTapInstalled)
        CZUserDefaults.shared.removeObject(forKey: CZSettingsKeys.keyHelperLastError)
    }

    private func teardownEventTap() {
        if eventTap != nil {
            NSLog("[CoverZipKeyHelper] event tap removed")
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        CZUserDefaults.shared.set(false, forKey: CZSettingsKeys.keyHelperIsEventTapInstalled)
    }

    @objc private func handlePreviewVisible(_ notification: Notification) {
        guard isKeyHelperEnabledForRuntime() else {
            NSLog("[CoverZipKeyHelper] visible ignored: helper disabled")
            CZUserDefaults.shared.set("visible ignored: helper disabled", forKey: CZSettingsKeys.keyHelperLastDecision)
            clearActiveSession()
            return
        }
        guard let sessionID = notification.userInfo?[CZPreviewVisibilityUserInfoKeys.sessionID] as? String else {
            NSLog("[CoverZipKeyHelper] visible ignored: missing sessionID")
            CZUserDefaults.shared.set("visible ignored: missing sessionID", forKey: CZSettingsKeys.keyHelperLastDecision)
            return
        }

        activeSessionID = sessionID
        visibleUntil = Date().addingTimeInterval(visibilityTimeout)
        if let isRightToLeft = notification.userInfo?[CZPreviewVisibilityUserInfoKeys.isRightToLeftReading] as? Bool {
            cachedIsRightToLeftReading = isRightToLeft
        }
        let now = Date().timeIntervalSince1970
        CZUserDefaults.shared.set(sessionID, forKey: CZSettingsKeys.keyHelperActiveSessionID)
        CZUserDefaults.shared.set(now, forKey: CZSettingsKeys.keyHelperLastVisibleAt)
        CZUserDefaults.shared.set(visibleUntil?.timeIntervalSince1970 ?? 0, forKey: CZSettingsKeys.keyHelperVisibleUntil)
        CZUserDefaults.shared.set("visible received", forKey: CZSettingsKeys.keyHelperLastDecision)
        NSLog("[CoverZipKeyHelper] visible session=%@", sessionID)
        refreshAccessibilityTrust(installIfNeeded: true, promptIfNeeded: true)
    }

    @objc private func handlePreviewHidden(_ notification: Notification) {
        guard let sessionID = notification.userInfo?[CZPreviewVisibilityUserInfoKeys.sessionID] as? String else {
            NSLog("[CoverZipKeyHelper] hidden without sessionID")
            CZUserDefaults.shared.set(Date().timeIntervalSince1970, forKey: CZSettingsKeys.keyHelperLastHiddenAt)
            clearActiveSession()
            return
        }
        if sessionID == activeSessionID {
            NSLog("[CoverZipKeyHelper] hidden session=%@", sessionID)
            CZUserDefaults.shared.set(Date().timeIntervalSince1970, forKey: CZSettingsKeys.keyHelperLastHiddenAt)
            clearActiveSession()
        }
    }

    @objc private func handleQuitRequested(_ notification: Notification) {
        NSLog("[CoverZipKeyHelper] quit requested")
        NSApp.terminate(nil)
    }

    @objc private func handlePreviewSessionCommandHandled(_ notification: Notification) {
        let commandID = (notification.userInfo?[CZPreviewSessionCommandUserInfoKeys.commandID] as? String)
            ?? (notification.object as? String)
        guard let commandID else { return }
        if finderFallbackUntil != nil {
            finderFallbackUntil = Date().addingTimeInterval(finderFallbackTimeout)
        }
        CZUserDefaults.shared.set("command handled \(commandID)", forKey: CZSettingsKeys.keyHelperLastDecision)
    }

    private func clearActiveSession() {
        activeSessionID = nil
        visibleUntil = nil
        CZUserDefaults.shared.removeObject(forKey: CZSettingsKeys.keyHelperActiveSessionID)
        CZUserDefaults.shared.removeObject(forKey: CZSettingsKeys.keyHelperVisibleUntil)
    }

    private func beginFinderFallbackSession(reason: String) {
        guard isFinderFallbackEnabledForRuntime() else { return }
        finderFallbackUntil = Date().addingTimeInterval(finderFallbackTimeout)
        CZUserDefaults.shared.set(reason, forKey: CZSettingsKeys.keyHelperLastDecision)
        NSLog("[CoverZipKeyHelper] finder fallback began: %@", reason)
    }

    private func clearFinderFallbackSession(reason: String) {
        guard finderFallbackUntil != nil else { return }
        finderFallbackUntil = nil
        CZUserDefaults.shared.set(reason, forKey: CZSettingsKeys.keyHelperLastDecision)
        NSLog("[CoverZipKeyHelper] finder fallback cleared: %@", reason)
    }

    private func rejectKeyEvent(reason: String, keyCode: Int64? = nil) -> Bool {
        CZUserDefaults.shared.set(reason, forKey: CZSettingsKeys.keyHelperLastDecision)
        if let keyCode {
            NSLog("[CoverZipKeyHelper] key %lld pass: %@", keyCode, reason)
        }
        return false
    }

    private func isKeyHelperEnabledForRuntime() -> Bool {
        // App Group が読めない未署名/診断環境では nil になり得る。
        // ヘルパーは設定 ON 時に起動されるため、未取得時は有効扱いにして診断可能にする。
        CZUserDefaults.shared.object(forKey: CZSettingsKeys.isKeyHelperEnabled) as? Bool ?? true
    }

    private func isFinderFallbackEnabledForRuntime() -> Bool {
        CZUserDefaults.shared.object(forKey: CZSettingsKeys.keyHelperFinderFallbackEnabled) as? Bool ?? true
    }

    private func isFinderFallbackActive(now: Date = Date()) -> Bool {
        guard let finderFallbackUntil else { return false }
        if finderFallbackUntil > now {
            return true
        }
        clearFinderFallbackSession(reason: "finder fallback expired")
        return false
    }

    private func updateFinderFallbackSessionForControlKey(_ keyCode: Int64, event: CGEvent, frontmostBundleID: String) {
        if keyCode == Self.escapeKeyCode {
            clearFinderFallbackSession(reason: "finder fallback closed by escape")
            return
        }
        let flags = CGEventFlags(rawValue: UInt64(event.flags.rawValue))
        if keyCode == Self.wKeyCode, flags.contains(.maskCommand) {
            clearFinderFallbackSession(reason: "finder fallback closed by command-w")
            return
        }
        guard frontmostBundleID == "com.apple.finder" else { return }
        guard keyCode == Self.spaceKeyCode else { return }
        if isFinderFallbackActive() {
            clearFinderFallbackSession(reason: "finder fallback toggled closed by space")
        } else {
            beginFinderFallbackSession(reason: "finder fallback began by space")
        }
    }

    private func shouldCaptureKeyEvent(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard commandForKeyCode(keyCode) != nil else {
            return false
        }

        didUseFinderFallbackForLastCapture = false
        let now = Date().timeIntervalSince1970
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        CZUserDefaults.shared.set(now, forKey: CZSettingsKeys.keyHelperLastKeyAt)
        CZUserDefaults.shared.set(Int(keyCode), forKey: CZSettingsKeys.keyHelperLastKeyCode)
        CZUserDefaults.shared.set(frontmostBundleID, forKey: CZSettingsKeys.keyHelperLastFrontmostBundleID)

        guard isKeyHelperEnabledForRuntime() else {
            return rejectKeyEvent(reason: "helper disabled", keyCode: keyCode)
        }
        guard isAccessibilityTrusted else {
            return rejectKeyEvent(reason: "accessibility not trusted", keyCode: keyCode)
        }
        if visibleUntil == nil || visibleUntil ?? .distantPast <= Date() {
            clearActiveSession()
            if frontmostBundleID == "com.apple.finder",
               isFinderFallbackEnabledForRuntime(),
               isFinderFallbackActive() {
                didUseFinderFallbackForLastCapture = true
                CZUserDefaults.shared.set("diagnostic Finder fallback active", forKey: CZSettingsKeys.keyHelperLastDecision)
                return true
            }

            let hasQuickLookWindow = isQuickLookWindowVisibleFallback()
            guard hasQuickLookWindow else {
                return rejectKeyEvent(reason: "no active visible QuickLook session", keyCode: keyCode)
            }
            CZUserDefaults.shared.set("fallback QuickLook window visible", forKey: CZSettingsKeys.keyHelperLastDecision)
        }
        guard allowedFrontmostBundleIDs.contains(frontmostBundleID) else {
            return rejectKeyEvent(reason: "frontmost not allowed: \(frontmostBundleID)", keyCode: keyCode)
        }

        CZUserDefaults.shared.set("capturing key \(keyCode)", forKey: CZSettingsKeys.keyHelperLastDecision)
        NSLog("[CoverZipKeyHelper] key %lld captured frontmost=%@", keyCode, frontmostBundleID)
        return true
    }

    private func isQuickLookWindowVisibleFallback() -> Bool {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            CZUserDefaults.shared.set("window list unavailable", forKey: CZSettingsKeys.keyHelperLastWindowSummary)
            return false
        }

        var summaries: [String] = []
        for windowInfo in windowInfoList {
            let ownerName = windowInfo[kCGWindowOwnerName as String] as? String ?? ""
            let windowName = windowInfo[kCGWindowName as String] as? String ?? ""
            let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
            let alpha = windowInfo[kCGWindowAlpha as String] as? Double ?? 1.0
            let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let x = bounds["X"] as? Int ?? 0
            let y = bounds["Y"] as? Int ?? 0
            let width = bounds["Width"] as? Int ?? 0
            let height = bounds["Height"] as? Int ?? 0

            guard layer == 0, alpha > 0 else { continue }
            let summary = "\(ownerName):\(windowName)[\(x),\(y),\(width)x\(height),L\(layer)]"
            if ownerName.localizedCaseInsensitiveContains("QuickLook")
                || ownerName.localizedCaseInsensitiveContains("Quick Look")
                || windowName.localizedCaseInsensitiveContains("QuickLook")
                || windowName.localizedCaseInsensitiveContains("Quick Look") {
                CZUserDefaults.shared.set(summary, forKey: CZSettingsKeys.keyHelperLastWindowSummary)
                NSLog("[CoverZipKeyHelper] QuickLook fallback window=%@", summary)
                return true
            }
            if summaries.count < 5, !ownerName.isEmpty || !windowName.isEmpty {
                summaries.append(summary)
            }
        }

        CZUserDefaults.shared.set(summaries.joined(separator: " | "), forKey: CZSettingsKeys.keyHelperLastWindowSummary)
        return false
    }

    private func handleKeyEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        updateFinderFallbackSessionForControlKey(keyCode, event: event, frontmostBundleID: frontmostBundleID)

        guard shouldCaptureKeyEvent(event) else {
            return Unmanaged.passUnretained(event)
        }

        guard let command = commandForKeyCode(keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        let commandID = UUID().uuidString
        if didUseFinderFallbackForLastCapture {
            finderFallbackUntil = Date().addingTimeInterval(finderFallbackTimeout)
        }
        DispatchQueue.main.async { [weak self] in
            self?.postCommand(command, commandID: commandID)
        }
        return nil
    }

    private func commandForKeyCode(_ keyCode: Int64) -> CZPreviewSessionCommand? {
        let isRightToLeft = cachedIsRightToLeftReading

        switch keyCode {
        case 123:
            return isRightToLeft ? .goForwardPage : .goBackwardPage
        case 124:
            return isRightToLeft ? .goBackwardPage : .goForwardPage
        case 125:
            return .goForwardPage
        case 126:
            return .goBackwardPage
        default:
            return nil
        }
    }

    private func readIsRightToLeftReadingFromDefaults() -> Bool {
        CZUserDefaults.shared.object(forKey: CZSettingsKeys.isRightToLeftReading) as? Bool ?? true
    }

    private func postCommand(_ command: CZPreviewSessionCommand, commandID: String) {
        NSLog("[CoverZipKeyHelper] post command=%@", command.rawValue)
        CZUserDefaults.shared.set(Date().timeIntervalSince1970, forKey: CZSettingsKeys.keyHelperLastCommandAt)
        CZUserDefaults.shared.set(command.rawValue, forKey: CZSettingsKeys.keyHelperLastCommand)
        CZUserDefaults.shared.set("posted \(command.rawValue)", forKey: CZSettingsKeys.keyHelperLastDecision)
        let userInfo: [String: Any] = [
            CZPreviewSessionCommandUserInfoKeys.command: command.rawValue,
            CZPreviewSessionCommandUserInfoKeys.commandID: commandID
        ]
        DistributedNotificationCenter.default().postNotificationName(
            CZDistributedNotifications.previewSessionCommand,
            object: command.rawValue,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    private static let keyEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<KeyHelperController>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NSLog("[CoverZipKeyHelper] event tap disabled type=%d, re-enabling", type.rawValue)
            CZUserDefaults.shared.set("event tap disabled, re-enabled", forKey: CZSettingsKeys.keyHelperLastDecision)
            if let eventTap = controller.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        return controller.handleKeyEvent(event)
    }
}

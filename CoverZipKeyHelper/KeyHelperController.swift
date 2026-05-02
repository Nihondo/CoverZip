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
    private let trustedCheckInterval: TimeInterval = 5.0
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
    private var trustedCheckTimer: Timer?
    private var isAccessibilityTrusted = false

    override init() {
        super.init()
        NSLog("[CoverZipKeyHelper] started")
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
            self?.refreshDiagnosticWindowSummary()
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
        let now = Date().timeIntervalSince1970
        CZUserDefaults.shared.set(sessionID, forKey: CZSettingsKeys.keyHelperActiveSessionID)
        CZUserDefaults.shared.set(now, forKey: CZSettingsKeys.keyHelperLastVisibleAt)
        CZUserDefaults.shared.set(visibleUntil?.timeIntervalSince1970 ?? 0, forKey: CZSettingsKeys.keyHelperVisibleUntil)
        CZUserDefaults.shared.set("visible received", forKey: CZSettingsKeys.keyHelperLastDecision)
        NSLog("[CoverZipKeyHelper] visible session=%@", sessionID)
        refreshAccessibilityTrust(installIfNeeded: true, promptIfNeeded: false)
    }

    @objc private func handlePreviewHidden(_ notification: Notification) {
        guard let sessionID = notification.userInfo?[CZPreviewVisibilityUserInfoKeys.sessionID] as? String else {
            NSLog("[CoverZipKeyHelper] hidden without sessionID")
            CZUserDefaults.shared.set(Date().timeIntervalSince1970, forKey: CZSettingsKeys.keyHelperLastHiddenAt)
            clearActiveSession()
            refreshDiagnosticWindowSummary()
            return
        }
        if sessionID == activeSessionID {
            NSLog("[CoverZipKeyHelper] hidden session=%@", sessionID)
            CZUserDefaults.shared.set(Date().timeIntervalSince1970, forKey: CZSettingsKeys.keyHelperLastHiddenAt)
            clearActiveSession()
            refreshDiagnosticWindowSummary()
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
        CZUserDefaults.shared.set("command handled \(commandID)", forKey: CZSettingsKeys.keyHelperLastDecision)
    }

    private func clearActiveSession() {
        activeSessionID = nil
        visibleUntil = nil
        CZUserDefaults.shared.removeObject(forKey: CZSettingsKeys.keyHelperActiveSessionID)
        CZUserDefaults.shared.removeObject(forKey: CZSettingsKeys.keyHelperVisibleUntil)
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

    private func shouldCaptureKeyEvent(keyCode: Int64, command: CZPreviewSessionCommand) -> Bool {
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
            guard isFrontmostQuickLookWindowVisible() else {
                return rejectKeyEvent(reason: "no active visible QuickLook session", keyCode: keyCode)
            }
            CZUserDefaults.shared.set("QuickLook AX window visible", forKey: CZSettingsKeys.keyHelperLastDecision)
        }
        guard allowedFrontmostBundleIDs.contains(frontmostBundleID) else {
            return rejectKeyEvent(reason: "frontmost not allowed: \(frontmostBundleID)", keyCode: keyCode)
        }

        CZUserDefaults.shared.set("capturing key \(keyCode)", forKey: CZSettingsKeys.keyHelperLastDecision)
        NSLog(
            "[CoverZipKeyHelper] key %lld captured command=%@ frontmost=%@",
            keyCode,
            command.rawValue,
            frontmostBundleID
        )
        return true
    }

    private func isFrontmostQuickLookWindowVisible() -> Bool {
        guard let frontmostSummary = resolveFrontmostWindowSummary() else {
            refreshDiagnosticWindowSummary()
            return false
        }
        recordFrontmostWindowSummary(frontmostSummary)
        if isQuickLookWindowCandidate(ownerName: frontmostSummary.applicationName, windowName: frontmostSummary.windowTitle) {
            NSLog("[CoverZipKeyHelper] QuickLook AX window=%@", frontmostSummary.diagnosticText)
            return true
        }
        return false
    }

    private func refreshDiagnosticWindowSummary() {
        guard let frontmostSummary = resolveFrontmostWindowSummary() else {
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            let bundleIdentifier = frontmostApplication?.bundleIdentifier ?? "unknown"
            let applicationName = frontmostApplication?.localizedName ?? "unknown"
            CZUserDefaults.shared.set(
                "AX:\(bundleIdentifier):\(applicationName):(no focused window)",
                forKey: CZSettingsKeys.keyHelperLastWindowSummary
            )
            return
        }
        recordFrontmostWindowSummary(frontmostSummary)
    }

    private func recordFrontmostWindowSummary(_ summary: FrontmostWindowSummary) {
        CZUserDefaults.shared.set(summary.diagnosticText, forKey: CZSettingsKeys.keyHelperLastWindowSummary)
    }

    private struct FrontmostWindowSummary {
        let applicationName: String
        let bundleIdentifier: String
        let windowTitle: String

        var diagnosticText: String {
            "AX:\(bundleIdentifier):\(applicationName):\(windowTitle)"
        }
    }

    private func resolveFrontmostWindowSummary() -> FrontmostWindowSummary? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return nil }
        let applicationElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
        guard let windowElement = resolveFocusedWindowElement(from: applicationElement),
              let windowTitle = resolveWindowTitle(from: windowElement) else {
            return nil
        }
        let applicationName = frontmostApplication.localizedName ?? ""
        let bundleIdentifier = frontmostApplication.bundleIdentifier ?? "unknown"
        return FrontmostWindowSummary(
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle
        )
    }

    private func resolveFocusedWindowElement(from applicationElement: AXUIElement) -> AXUIElement? {
        if let focusedWindowValue = copyAttributeValue(
            of: applicationElement,
            attribute: kAXFocusedWindowAttribute as CFString
        ), CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID() {
            return unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        }

        guard let focusedElementValue = copyAttributeValue(
            of: applicationElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ), CFGetTypeID(focusedElementValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let focusedElement = unsafeBitCast(focusedElementValue, to: AXUIElement.self)
        guard let windowElementValue = copyAttributeValue(
            of: focusedElement,
            attribute: kAXWindowAttribute as CFString
        ), CFGetTypeID(windowElementValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(windowElementValue, to: AXUIElement.self)
    }

    private func resolveWindowTitle(from windowElement: AXUIElement) -> String? {
        guard let windowTitleValue = copyAttributeValue(
            of: windowElement,
            attribute: kAXTitleAttribute as CFString
        ), let windowTitle = normalizeTextValue(windowTitleValue) else {
            return nil
        }
        let normalizedWindowTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedWindowTitle.isEmpty ? nil : normalizedWindowTitle
    }

    private func copyAttributeValue(of element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var attributeValue: CFTypeRef?
        let copyStatus = AXUIElementCopyAttributeValue(element, attribute, &attributeValue)
        guard copyStatus == .success else { return nil }
        return attributeValue
    }

    private func normalizeTextValue(_ value: CFTypeRef) -> String? {
        if let plainText = value as? String {
            return plainText
        }
        if let attributedText = value as? NSAttributedString {
            return attributedText.string
        }
        return nil
    }

    private func isQuickLookWindowCandidate(ownerName: String, windowName: String) -> Bool {
        if ownerName.localizedCaseInsensitiveContains("QuickLook")
            || ownerName.localizedCaseInsensitiveContains("Quick Look")
            || ownerName.localizedCaseInsensitiveContains("クイックルック")
            || windowName.localizedCaseInsensitiveContains("QuickLook")
            || windowName.localizedCaseInsensitiveContains("Quick Look")
            || windowName.localizedCaseInsensitiveContains("クイックルック") {
            return true
        }

        let normalizedTitle = windowName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTitle.isEmpty else { return false }
        return normalizedTitle.hasSuffix(".zip") || normalizedTitle.contains(".zip ")
    }

    private func handleKeyEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        guard let command = commandForKeyCode(keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        guard shouldCaptureKeyEvent(keyCode: keyCode, command: command) else {
            return Unmanaged.passUnretained(event)
        }

        let commandID = UUID().uuidString
        DispatchQueue.main.async { [weak self] in
            self?.postCommand(command, commandID: commandID)
        }
        return nil
    }

    private func commandForKeyCode(_ keyCode: Int64) -> CZPreviewSessionCommand? {
        switch keyCode {
        case 123: return .goLeftArrowPage
        case 124: return .goRightArrowPage
        case 125: return .goForwardPage
        case 126: return .goBackwardPage
        default:  return nil
        }
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

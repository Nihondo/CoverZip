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
    private let visibilityTimeout: TimeInterval = 15.0
    private let trustedCheckInterval: TimeInterval = 5.0
    private let finderBundleIdentifier = "com.apple.finder"
    private let fullscreenWindowSizeTolerance: CGFloat = 2.0

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
        setupDarwinNotificationObservers()
        refreshAccessibilityTrust(installIfNeeded: true, promptIfNeeded: isKeyHelperEnabledForRuntime())
        startTrustedCheckTimer()
    }

    deinit {
        NSLog("[CoverZipKeyHelper] deinit")
        teardownEventTap()
        DistributedNotificationCenter.default().removeObserver(self)
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
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

    private func setupDarwinNotificationObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center, selfPtr,
            KeyHelperController.darwinVisibleCallback,
            CZDarwinNotifications.qlVisible as CFString,
            nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, selfPtr,
            KeyHelperController.darwinHiddenCallback,
            CZDarwinNotifications.qlHidden as CFString,
            nil, .deliverImmediately
        )
    }

    private static let darwinVisibleCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let controller = Unmanaged<KeyHelperController>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async { controller.onDarwinVisible() }
    }

    private static let darwinHiddenCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let controller = Unmanaged<KeyHelperController>.fromOpaque(observer).takeUnretainedValue()
        DispatchQueue.main.async { controller.onDarwinHidden() }
    }

    private func onDarwinVisible() {
        visibleUntil = Date().addingTimeInterval(visibilityTimeout)
        CZUserDefaults.shared.set(Date().timeIntervalSince1970, forKey: CZSettingsKeys.keyHelperLastVisibleAt)
        CZUserDefaults.shared.set("darwin visible", forKey: CZSettingsKeys.keyHelperLastDecision)
        NSLog("[CoverZipKeyHelper] darwin ql visible, visibleUntil=%@", visibleUntil?.description ?? "nil")
    }

    private func onDarwinHidden() {
        clearActiveSession()
        CZUserDefaults.shared.set(Date().timeIntervalSince1970, forKey: CZSettingsKeys.keyHelperLastHiddenAt)
        CZUserDefaults.shared.set("darwin hidden", forKey: CZSettingsKeys.keyHelperLastDecision)
        NSLog("[CoverZipKeyHelper] darwin ql hidden")
        refreshDiagnosticWindowSummary()
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
        guard let visibleUntil, visibleUntil > Date() else {
            clearActiveSession()
            return rejectKeyEvent(reason: "no active visible QuickLook session", keyCode: keyCode)
        }
        guard isFrontmostQuickLookWindowVisible() else {
            return rejectKeyEvent(reason: "no AX-visible QuickLook window", keyCode: keyCode)
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
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            refreshDiagnosticWindowSummary()
            return false
        }

        let axSummaries = resolveFrontmostWindowSummaries(for: frontmostApplication)
        if let quickLookSummary = axSummaries.first(where: {
            isQuickLookWindowCandidate(ownerName: "\($0.bundleIdentifier) \($0.applicationName)", windowName: $0.windowTitle)
        }) {
            recordWindowSummary(quickLookSummary.diagnosticText)
            NSLog("[CoverZipKeyHelper] QuickLook AX window=%@", quickLookSummary.diagnosticText)
            return true
        }

        if isFinderApplication(frontmostApplication) {
            let finderSummary = resolveFinderFullscreenWindowSummary(for: frontmostApplication)
            if finderSummary.isFullscreenPair {
                recordWindowSummary(finderSummary.diagnosticText)
                NSLog("[CoverZipKeyHelper] QuickLook Finder fullscreen window pair=%@", finderSummary.diagnosticText)
                return true
            }
            recordWindowSummary(makeRejectedWindowSummary(axSummaries: axSummaries, finderSummary: finderSummary))
            return false
        }

        if let firstSummary = axSummaries.first {
            recordWindowSummary(firstSummary.diagnosticText)
        } else {
            recordNoAXWindowSummary(frontmostApplication)
        }
        return false
    }

    private func refreshDiagnosticWindowSummary() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            recordWindowSummary("AX:unknown:unknown:(no frontmost app)")
            return
        }

        let axSummaries = resolveFrontmostWindowSummaries(for: frontmostApplication)
        if isFinderApplication(frontmostApplication) {
            let finderSummary = resolveFinderFullscreenWindowSummary(for: frontmostApplication)
            recordWindowSummary(makeRejectedWindowSummary(axSummaries: axSummaries, finderSummary: finderSummary))
            return
        }

        if let firstSummary = axSummaries.first {
            recordWindowSummary(firstSummary.diagnosticText)
        } else {
            recordNoAXWindowSummary(frontmostApplication)
        }
    }

    private func recordWindowSummary(_ summary: String) {
        CZUserDefaults.shared.set(summary, forKey: CZSettingsKeys.keyHelperLastWindowSummary)
    }

    private func recordNoAXWindowSummary(_ application: NSRunningApplication) {
        let bundleIdentifier = application.bundleIdentifier ?? "unknown"
        let applicationName = application.localizedName ?? "unknown"
        recordWindowSummary("AX:none:\(bundleIdentifier):\(applicationName):(no window)")
    }

    private func makeRejectedWindowSummary(
        axSummaries: [FrontmostWindowSummary],
        finderSummary: FinderFullscreenWindowSummary
    ) -> String {
        if let firstSummary = axSummaries.first {
            return "\(firstSummary.diagnosticText) | \(finderSummary.diagnosticText)"
        }
        return "AX:none:com.apple.finder:Finder:(no window) | \(finderSummary.diagnosticText)"
    }

    private struct FrontmostWindowSummary {
        let applicationName: String
        let bundleIdentifier: String
        let source: String
        let windowTitle: String

        var diagnosticText: String {
            let title = windowTitle.isEmpty ? "(no title)" : windowTitle
            return "AX:\(source):\(bundleIdentifier):\(applicationName):\(title)"
        }
    }

    private struct FinderFullscreenWindowSummary {
        let isFullscreenPair: Bool
        let diagnosticText: String
    }

    private struct DisplayPixelSize {
        let width: Int
        let height: Int

        var label: String {
            "\(width)x\(height)"
        }
    }

    private struct FinderWindowInfo {
        let windowID: Int
        let bounds: CGRect

        var sizeLabel: String {
            "\(Int(bounds.width.rounded()))x\(Int(bounds.height.rounded()))"
        }

        var diagnosticText: String {
            let x = Int(bounds.origin.x.rounded())
            let y = Int(bounds.origin.y.rounded())
            return "id=\(windowID) size=\(sizeLabel) origin=\(x),\(y)"
        }
    }

    private func resolveFrontmostWindowSummaries(for application: NSRunningApplication) -> [FrontmostWindowSummary] {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var summaries: [FrontmostWindowSummary] = []

        if let focusedWindow = resolveAXWindowElement(
            from: applicationElement,
            attribute: kAXFocusedWindowAttribute as CFString
        ) {
            summaries.append(makeFrontmostWindowSummary(application, focusedWindow, source: "focusedWindow"))
        }

        if let focusedElementWindow = resolveFocusedElementWindow(from: applicationElement) {
            summaries.append(makeFrontmostWindowSummary(application, focusedElementWindow, source: "focusedElement.window"))
        }

        for (index, windowElement) in resolveAXWindowList(from: applicationElement).enumerated() {
            summaries.append(makeFrontmostWindowSummary(application, windowElement, source: "windows[\(index)]"))
        }
        return summaries
    }

    private func makeFrontmostWindowSummary(
        _ application: NSRunningApplication,
        _ windowElement: AXUIElement,
        source: String
    ) -> FrontmostWindowSummary {
        FrontmostWindowSummary(
            applicationName: application.localizedName ?? "",
            bundleIdentifier: application.bundleIdentifier ?? "unknown",
            source: source,
            windowTitle: resolveWindowTitle(from: windowElement) ?? ""
        )
    }

    private func resolveFocusedElementWindow(from applicationElement: AXUIElement) -> AXUIElement? {
        guard let focusedElement = resolveAXWindowElement(
            from: applicationElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else {
            return nil
        }
        return resolveAXWindowElement(from: focusedElement, attribute: kAXWindowAttribute as CFString)
    }

    private func resolveAXWindowElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        guard let elementValue = copyAttributeValue(
            of: element,
            attribute: attribute
        ), CFGetTypeID(elementValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(elementValue, to: AXUIElement.self)
    }

    private func resolveAXWindowList(from applicationElement: AXUIElement) -> [AXUIElement] {
        guard let windowsValue = copyAttributeValue(
            of: applicationElement,
            attribute: kAXWindowsAttribute as CFString
        ), CFGetTypeID(windowsValue) == CFArrayGetTypeID(),
              let rawWindows = windowsValue as? [AnyObject] else {
            return []
        }

        return rawWindows.compactMap { rawWindow in
            let windowValue = rawWindow as CFTypeRef
            guard CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(windowValue, to: AXUIElement.self)
        }
    }

    private func resolveFinderFullscreenWindowSummary(
        for application: NSRunningApplication
    ) -> FinderFullscreenWindowSummary {
        let displaySizes = resolveOnlineDisplayPixelSizes()
        let finderWindows = resolveOnscreenFinderWindows(processIdentifier: application.processIdentifier)
        let fullscreenCandidates = finderWindows.filter { window in
            displaySizes.contains { isWindow(window.bounds.size, equalTo: $0) }
        }

        if let match = findFullscreenWindowPair(in: fullscreenCandidates, displaySizes: displaySizes) {
            return FinderFullscreenWindowSummary(
                isFullscreenPair: true,
                diagnosticText: makeFinderPairDiagnostic(displaySize: match.displaySize, windows: match.windows)
            )
        }

        return FinderFullscreenWindowSummary(
            isFullscreenPair: false,
            diagnosticText: makeFinderNoPairDiagnostic(
                displaySizes: displaySizes,
                windowCount: finderWindows.count,
                candidates: fullscreenCandidates
            )
        )
    }

    private func resolveOnlineDisplayPixelSizes() -> [DisplayPixelSize] {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else { return [] }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetOnlineDisplayList(displayCount, &displays, &displayCount) == .success else { return [] }
        return displays.prefix(Int(displayCount)).map {
            DisplayPixelSize(width: Int(CGDisplayPixelsWide($0)), height: Int(CGDisplayPixelsHigh($0)))
        }
    }

    private func resolveOnscreenFinderWindows(processIdentifier: pid_t) -> [FinderWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { windowInfo in
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.int32Value == processIdentifier,
                  let bounds = resolveWindowBounds(from: windowInfo) else {
                return nil
            }
            let windowID = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
            return FinderWindowInfo(windowID: windowID, bounds: bounds)
        }
    }

    private func resolveWindowBounds(from windowInfo: [String: Any]) -> CGRect? {
        guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else { return nil }
        var bounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds) else { return nil }
        return bounds
    }

    private func findFullscreenWindowPair(
        in windows: [FinderWindowInfo],
        displaySizes: [DisplayPixelSize]
    ) -> (displaySize: DisplayPixelSize, windows: [FinderWindowInfo])? {
        for displaySize in displaySizes {
            let matchingWindows = windows.filter { isWindow($0.bounds.size, equalTo: displaySize) }
            let windowsByOrigin = Dictionary(grouping: matchingWindows) { roundedOriginKey(for: $0.bounds.origin) }
            if let pair = windowsByOrigin.values.first(where: { $0.count >= 2 }) {
                return (displaySize, Array(pair.prefix(4)))
            }
        }
        return nil
    }

    private func isWindow(_ windowSize: CGSize, equalTo displaySize: DisplayPixelSize) -> Bool {
        abs(windowSize.width - CGFloat(displaySize.width)) <= fullscreenWindowSizeTolerance
            && abs(windowSize.height - CGFloat(displaySize.height)) <= fullscreenWindowSizeTolerance
    }

    private func roundedOriginKey(for origin: CGPoint) -> String {
        "\(Int(origin.x.rounded())):\(Int(origin.y.rounded()))"
    }

    private func makeFinderPairDiagnostic(displaySize: DisplayPixelSize, windows: [FinderWindowInfo]) -> String {
        let windowText = windows.map(\.diagnosticText).joined(separator: ";")
        return "CGWindow:Finder fullscreen pair display=\(displaySize.label) count=\(windows.count) windows=\(windowText)"
    }

    private func makeFinderNoPairDiagnostic(
        displaySizes: [DisplayPixelSize],
        windowCount: Int,
        candidates: [FinderWindowInfo]
    ) -> String {
        let displays = displaySizes.map(\.label).joined(separator: ",")
        let candidateText = candidates.prefix(4).map(\.diagnosticText).joined(separator: ";")
        return "CGWindow:Finder fullscreen pair not found displays=\(displays) windows=\(windowCount) matched=\(candidates.count) candidates=\(candidateText)"
    }

    private func isFinderApplication(_ application: NSRunningApplication) -> Bool {
        application.bundleIdentifier == finderBundleIdentifier
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

        guard let previewCommand = commandForKeyEvent(event) else {
            return Unmanaged.passUnretained(event)
        }

        guard shouldCaptureKeyEvent(keyCode: keyCode, command: previewCommand.command) else {
            return Unmanaged.passUnretained(event)
        }

        let commandID = UUID().uuidString
        DispatchQueue.main.async { [weak self] in
            self?.postCommand(previewCommand.command, commandID: commandID, intValue: previewCommand.intValue)
        }
        return nil
    }

    private func commandForKeyEvent(_ event: CGEvent) -> (command: CZPreviewSessionCommand, intValue: Int?)? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isCommand = flags.contains(.maskCommand)
        let isShift = flags.contains(.maskShift)

        switch keyCode {
        case 123:
            if isCommand { return (.goToLeftArrowEdgePage, nil) }
            if isShift { return (.jumpLeftArrowPages, 10) }
            return (.goLeftArrowPage, nil)
        case 124:
            if isCommand { return (.goToRightArrowEdgePage, nil) }
            if isShift { return (.jumpRightArrowPages, 10) }
            return (.goRightArrowPage, nil)
        case 125:
            return (.goForwardPage, nil)
        case 126:
            return (.goBackwardPage, nil)
        case 115:
            return (.goToFirstPage, nil)
        case 119:
            return (.goToLastPage, nil)
        case 116:
            return (.jumpRelativePages, -10)
        case 121:
            return (.jumpRelativePages, 10)
        default:
            return nil
        }
    }

    private func postCommand(_ command: CZPreviewSessionCommand, commandID: String, intValue: Int? = nil) {
        if let intValue {
            NSLog("[CoverZipKeyHelper] post command=%@ intValue=%d", command.rawValue, intValue)
        } else {
            NSLog("[CoverZipKeyHelper] post command=%@", command.rawValue)
        }
        CZUserDefaults.shared.set(Date().timeIntervalSince1970, forKey: CZSettingsKeys.keyHelperLastCommandAt)
        CZUserDefaults.shared.set(command.rawValue, forKey: CZSettingsKeys.keyHelperLastCommand)
        let decision = intValue.map { "posted \(command.rawValue) intValue=\($0)" } ?? "posted \(command.rawValue)"
        CZUserDefaults.shared.set(decision, forKey: CZSettingsKeys.keyHelperLastDecision)
        var userInfo: [String: Any] = [
            CZPreviewSessionCommandUserInfoKeys.command: command.rawValue,
            CZPreviewSessionCommandUserInfoKeys.commandID: commandID
        ]
        if let intValue {
            userInfo[CZPreviewSessionCommandUserInfoKeys.intValue] = intValue
        }
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

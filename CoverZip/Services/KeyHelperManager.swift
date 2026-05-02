//
//  KeyHelperManager.swift
//  CoverZip
//
//  Finder QuickLook 用キー入力ヘルパーの登録と状態確認
//

import AppKit
import Foundation
import ServiceManagement

/// Finder QuickLook 用キー入力ヘルパーのログイン項目登録を管理する。
final class KeyHelperManager {
    static let shared = KeyHelperManager()

    private let helperBundleIdentifier = "com.dmng.CoverZip.KeyHelper"

    private var loginItem: SMAppService {
        SMAppService.loginItem(identifier: helperBundleIdentifier)
    }

    private init() {}

    var status: SMAppService.Status {
        loginItem.status
    }

    var statusText: String {
        switch status {
        case .notRegistered:
            return CZLocalized.string("settings.key_helper.status.not_registered", defaultValue: "Not registered")
        case .enabled:
            return CZLocalized.string("settings.key_helper.status.enabled", defaultValue: "Enabled")
        case .requiresApproval:
            return CZLocalized.string("settings.key_helper.status.requires_approval", defaultValue: "Requires approval in Login Items")
        case .notFound:
            return CZLocalized.string("settings.key_helper.status.not_found", defaultValue: "Helper app not found")
        @unknown default:
            return CZLocalized.string("settings.key_helper.status.unknown", defaultValue: "Unknown")
        }
    }

    var isHelperAccessibilityTrusted: Bool {
        CZUserDefaults.shared.object(forKey: CZSettingsKeys.keyHelperLastAccessibilityTrusted) as? Bool ?? false
    }

    var diagnosticLines: [String] {
        let defaults = CZUserDefaults.shared
        return [
            "Accessibility: \(boolText(defaults.object(forKey: CZSettingsKeys.keyHelperLastAccessibilityTrusted) as? Bool))",
            "Event tap: \(boolText(defaults.object(forKey: CZSettingsKeys.keyHelperIsEventTapInstalled) as? Bool))",
            "Active session: \(defaults.string(forKey: CZSettingsKeys.keyHelperActiveSessionID) ?? "-")",
            "Visible until: \(dateText(defaults.double(forKey: CZSettingsKeys.keyHelperVisibleUntil)))",
            "Last visible: \(dateText(defaults.double(forKey: CZSettingsKeys.keyHelperLastVisibleAt)))",
            "Last hidden: \(dateText(defaults.double(forKey: CZSettingsKeys.keyHelperLastHiddenAt)))",
            "Last key: \(lastKeyText(defaults: defaults))",
            "Last frontmost: \(defaults.string(forKey: CZSettingsKeys.keyHelperLastFrontmostBundleID) ?? "-")",
            "Last decision: \(defaults.string(forKey: CZSettingsKeys.keyHelperLastDecision) ?? "-")",
            "Window summary: \(defaults.string(forKey: CZSettingsKeys.keyHelperLastWindowSummary) ?? "-")",
            "Last command: \(lastCommandText(defaults: defaults))",
            "Preview posted: \(lastPreviewPostText(defaults: defaults))",
            "Last error: \(defaults.string(forKey: CZSettingsKeys.keyHelperLastError) ?? "-")"
        ]
    }

    func enable() throws {
        do {
            let registrationNeeded = loginItem.status == .notRegistered || loginItem.status == .notFound
            if registrationNeeded {
                try loginItem.register()
                // register() がヘルパーを即時起動するため、二重起動を避けて明示的な起動はスキップ
            }
            CZSettings.shared.isKeyHelperEnabled = true
            if !registrationNeeded {
                launchHelperIfPossible()
            }
        } catch {
            CZSettings.shared.isKeyHelperEnabled = false
            throw error
        }
    }

    func disable() throws {
        CZSettings.shared.isKeyHelperEnabled = false
        DistributedNotificationCenter.default().postNotificationName(
            CZDistributedNotifications.keyHelperQuitRequested,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )

        do {
            if loginItem.status == .enabled || loginItem.status == .requiresApproval {
                try loginItem.unregister()
            }
        } catch {
            throw error
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func repairRegistrationIfNeeded() {
        guard CZSettings.shared.isKeyHelperEnabled else { return }
        do {
            let registrationNeeded = loginItem.status == .notRegistered || loginItem.status == .notFound
            if registrationNeeded {
                try loginItem.register()
                // register() がヘルパーを即時起動するため、二重起動を避けて明示的な起動はスキップ
            } else {
                launchHelperIfPossible()
            }
        } catch {
            CZUserDefaults.shared.set(error.localizedDescription, forKey: CZSettingsKeys.keyHelperLastError)
        }
    }

    private func launchHelperIfPossible() {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("LoginItems")
            .appendingPathComponent("CoverZipKeyHelper.app")

        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            CZUserDefaults.shared.set("CoverZipKeyHelper.app is missing from LoginItems", forKey: CZSettingsKeys.keyHelperLastError)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { _, error in
            if let error {
                CZUserDefaults.shared.set(error.localizedDescription, forKey: CZSettingsKeys.keyHelperLastError)
            }
        }
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else { return "-" }
        return value ? "true" : "false"
    }

    private func dateText(_ timestamp: Double) -> String {
        guard timestamp > 0 else { return "-" }
        let date = Date(timeIntervalSince1970: timestamp)
        return Self.dateFormatter.string(from: date)
    }

    private func lastKeyText(defaults: UserDefaults) -> String {
        let timestamp = defaults.double(forKey: CZSettingsKeys.keyHelperLastKeyAt)
        guard timestamp > 0 else { return "-" }
        let keyCode = defaults.object(forKey: CZSettingsKeys.keyHelperLastKeyCode) as? Int
        return "\(keyCode.map { String($0) } ?? "?") at \(dateText(timestamp))"
    }

    private func lastCommandText(defaults: UserDefaults) -> String {
        let timestamp = defaults.double(forKey: CZSettingsKeys.keyHelperLastCommandAt)
        guard timestamp > 0 else { return "-" }
        let command = defaults.string(forKey: CZSettingsKeys.keyHelperLastCommand) ?? "?"
        return "\(command) at \(dateText(timestamp))"
    }

    private func lastPreviewPostText(defaults: UserDefaults) -> String {
        let timestamp = defaults.double(forKey: CZSettingsKeys.previewLastVisibilityPostAt)
        guard timestamp > 0 else { return "-" }
        let name = defaults.string(forKey: CZSettingsKeys.previewLastVisibilityPostName) ?? "?"
        let sessionID = defaults.string(forKey: CZSettingsKeys.previewLastVisibilitySessionID) ?? "?"
        return "\(name) at \(dateText(timestamp)) session=\(sessionID)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

//
//  SettingsMenuCommands.swift
//  CoverZip
//
//  Created by Codex on 2026/03/13.
//

import AppKit
import SwiftUI

struct SettingsMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updateController = AppUpdateController.shared

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                presentAboutPanel()
            }
            label: {
                Label(
                    CZLocalized.string("menu.app.about", defaultValue: "About CoverZip"),
                    systemImage: "info.circle"
                )
            }
        }

        CommandGroup(after: .appInfo) {
            Divider()

            Button {
                updateController.checkForUpdates()
            }
            label: {
                Label(
                    CZLocalized.string("menu.app.check_for_updates", defaultValue: "Check for Updates..."),
                    systemImage: "arrow.down.circle"
                )
            }
            .disabled(!updateController.canCheckForUpdates)
        }

        CommandGroup(replacing: .appSettings) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                SettingsDiagnosticsState.shared.isVisible = NSEvent.modifierFlags.contains(.shift)
                openWindow(id: AppWindowIdentifier.settings)
            }
            label: {
                Label(
                    CZLocalized.string("menu.app.settings", defaultValue: "Settings…"),
                    systemImage: "gearshape"
                )
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(replacing: .help) {
            Button {
                openManual()
            }
            label: {
                Label(
                    CZLocalized.string("menu.help.manual", defaultValue: "CoverZip Manual"),
                    systemImage: "questionmark.circle"
                )
            }
        }
    }

    private func presentAboutPanel() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .credits: makeAboutCredits()
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeAboutCredits() -> NSAttributedString {
        let copyright = resolveAboutCopyright()
        let websiteURLString = "https://products.desireforwealth.com/products/coverzip"
        let creditsText = "\(copyright)\nWebsite: \(websiteURLString)"
        let attributed = NSMutableAttributedString(string: creditsText)
        let linkRange = (creditsText as NSString).range(of: websiteURLString)
        attributed.addAttribute(.link, value: websiteURLString, range: linkRange)
        return attributed
    }

    private func resolveAboutCopyright() -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return "Copyright © 2025-2026 Nihondo"
    }

    private func openManual() {
        guard let url = URL(string: "https://products.desireforwealth.com/products/coverzip-manual") else { return }
        NSWorkspace.shared.open(url)
    }
}

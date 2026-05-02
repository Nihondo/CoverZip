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

    var body: some Commands {
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
    }
}

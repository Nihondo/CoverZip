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
            Button(CZLocalized.string("menu.app.settings", defaultValue: "Settings…")) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: AppWindowIdentifier.settings)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}

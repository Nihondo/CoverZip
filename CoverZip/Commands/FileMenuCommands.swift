//
//  FileMenuCommands.swift
//  CoverZip
//
//  ファイルメニューに「ファイルを開く」と「内蔵ビューアで開く」を追加
//

import SwiftUI

struct FileMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(CZLocalized.string("menu.file.open", defaultValue: "Open File…")) {
                FileOpenPanelService.presentAndRouteZip()
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button(CZLocalized.string("menu.file.open_internal", defaultValue: "Open with Built-in Viewer…")) {
                FileOpenPanelService.presentAndOpenZip()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
        }
    }
}

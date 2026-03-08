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
            Button {
                FileOpenPanelService.presentAndRouteZip()
            } label: {
                Label(
                    CZLocalized.string("menu.file.open", defaultValue: "Open File…"),
                    systemImage: CZMenuSymbols.fileOpen
                )
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button {
                FileOpenPanelService.presentAndOpenZip()
            } label: {
                Label(
                    CZLocalized.string("menu.file.open_internal", defaultValue: "Open with Built-in Viewer…"),
                    systemImage: CZMenuSymbols.fileOpenInternal
                )
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
        }
    }
}

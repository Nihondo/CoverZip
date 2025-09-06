//
//  DebugMenuCommands.swift
//  CoverZip
//
//  Quick Look の最小テストを起動する開発メニュー（DEBUGビルドのみ）
//

#if DEBUG
import SwiftUI

struct DebugMenuCommands: Commands {
    var body: some Commands {
        CommandMenu("開発") {
            Button("QuickLook 入力ドライバテスト…") {
                QLPreviewInputDriver.presentAndOpen()
            }
        }
    }
}
#endif

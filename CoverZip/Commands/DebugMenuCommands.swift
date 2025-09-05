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
            Button("QuickLook スモークテスト…") {
                QLPreviewSmokeTest.presentAndOpen()
            }
            Divider()
            Toggle(isOn: Binding<Bool>(
                get: { InternalViewer.isSafeInputModeEnabled },
                set: { InternalViewer.isSafeInputModeEnabled = $0 }
            )) {
                Text("内蔵ビューア: セーフ入力モード")
            }
        }
    }
}
#endif

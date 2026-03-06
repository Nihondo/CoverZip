//
//  PreviewSettingsView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/08/26.
//

import SwiftUI

@available(macOS 13.0, *)
struct PreviewSettingsView: View {
    @StateObject private var settings = AppSettingsWriter.shared

    var body: some View {
        Form {
            Section {
                Picker("デフォルトページ方向:", selection: Binding(
                    get: { settings.isRightToLeftReading },
                    set: { settings.isRightToLeftReading = $0 }
                )) {
                    Text("右綴じ").tag(true)
                    Text("左綴じ").tag(false)
                }
                .pickerStyle(.segmented)
            } header: {
                Label("ページ方向", systemImage: "text.alignright")
            } footer: {
                Text("右綴じの場合、左クリックで次ページ、右クリックで前ページに移動します")
            }

            Section {
                Picker("デフォルト表示モード:", selection: Binding(
                    get: { settings.defaultViewMode },
                    set: { settings.defaultViewMode = $0 }
                )) {
                    Text("自動").tag(ViewModePreference.auto)
                    Text("単ページ").tag(ViewModePreference.single)
                    Text("見開き").tag(ViewModePreference.spread)
                }
                .pickerStyle(.segmented)

                Toggle("表紙を常に単ページ表示", isOn: Binding(
                    get: { settings.alwaysSinglePageForCover },
                    set: { settings.alwaysSinglePageForCover = $0 }
                ))
            } header: {
                Label("表示モード", systemImage: "rectangle.split.2x1")
            } footer: {
                Text("自動モードでは、ウィンドウの縦横比に応じて表示モードを自動選択します")
            }

            Section {
                Picker("方針:", selection: Binding(
                    get: { settings.imageDecodeCachePolicy },
                    set: { settings.imageDecodeCachePolicy = $0 }
                )) {
                    Text("しない").tag(CZImageDecodeCachePolicy.noCache)
                    Text("遅延（推奨）").tag(CZImageDecodeCachePolicy.deferred)
                    Text("即時（最速/メモリ多め）").tag(CZImageDecodeCachePolicy.immediate)
                }
                .pickerStyle(.segmented)
            } header: {
                Label("画像デコードキャッシュ", systemImage: "memorychip")
            } footer: {
                Text("遅延は初回だけデコードし、以降は再デコードを避けて滑らかに表示します。")
            }

            Section {
                HStack {
                    Text("ページ送り間隔:")
                    Spacer()
                    Text("\(String(format: "%.1f", settings.slideshowInterval))秒")
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { settings.slideshowInterval },
                        set: { settings.slideshowInterval = $0 }
                    ),
                    in: 1.0...10.0,
                    step: 0.5
                )
            } header: {
                Label("スライドショー", systemImage: "play.rectangle")
            } footer: {
                Text("コンテキストメニューからスライドショーを開始し、この間隔で自動ページ送りします")
            }

            Section {
                Toggle("ウィンドウサイズ・位置を復元", isOn: Binding(
                    get: { settings.restoreWindowFrameEnabled },
                    set: { settings.restoreWindowFrameEnabled = $0 }
                ))

                if settings.savedWindowFrameString != nil {
                    Button("保存されたサイズ情報をリセット", role: .destructive) {
                        settings.savedWindowFrameString = nil
                    }
                }
            } header: {
                Label("ウィンドウ", systemImage: "macwindow")
            } footer: {
                Text("有効にすると、前回のプレビューウィンドウのサイズと位置で次回開きます")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 400)
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        PreviewSettingsView()
    } else {
        // Fallback on earlier versions
    }
}

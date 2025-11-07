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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding(.bottom, 16)

                Divider()
                    .padding(.vertical, 8)

                readingDirectionSection

                Divider()
                    .padding(.vertical, 8)

                displayModeSection

                Divider()
                    .padding(.vertical, 8)

                decodeCacheSection

                Divider()
                    .padding(.vertical, 8)

                slideshowSection

                Divider()
                    .padding(.vertical, 8)

                windowSection
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 500)
    }

    private var decodeCacheSection: some View {
        GroupBox(label: sectionLabel("画像デコードキャッシュ", systemImage: "memorychip")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("方針:")
                    Picker("", selection: Binding(
                        get: { settings.imageDecodeCachePolicy },
                        set: { settings.imageDecodeCachePolicy = $0 }
                    )) {
                        Text("しない").tag(CZImageDecodeCachePolicy.noCache)
                        Text("遅延（推奨）").tag(CZImageDecodeCachePolicy.deferred)
                        Text("即時（最速/メモリ多め）").tag(CZImageDecodeCachePolicy.immediate)
                    }
                    .pickerStyle(.segmented)
                }
                Text("プレビュー拡張のデコードキャッシュ方針を切り替えます。遅延は初回だけデコードし、以降は再デコードを避けて滑らかに表示します。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("プレビュー設定")
                .font(.title2)
                .fontWeight(.semibold)
            Text("QuickLookプレビューの表示方法を設定します")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var readingDirectionSection: some View {
        GroupBox(label: sectionLabel("ページ方向", systemImage: "text.alignright")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("デフォルトページ方向:")
                    Picker("", selection: Binding(
                        get: { settings.isRightToLeftReading },
                        set: { settings.isRightToLeftReading = $0 }
                    )) {
                        Text("右綴じ").tag(true)
                        Text("左綴じ").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                Text("右綴じの場合、左クリックで次ページ、右クリックで前ページに移動します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var displayModeSection: some View {
        GroupBox(label: sectionLabel("表示モード", systemImage: "rectangle.split.2x1")) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("表紙を常に単ページ表示", isOn: Binding(
                    get: { settings.alwaysSinglePageForCover },
                    set: { settings.alwaysSinglePageForCover = $0 }
                ))
                .toggleStyle(.switch)

                HStack(spacing: 12) {
                    Text("デフォルト表示モード:")
                    Picker("", selection: Binding(
                        get: { settings.defaultViewMode },
                        set: { settings.defaultViewMode = $0 }
                    )) {
                        Text("自動").tag(ViewModePreference.auto)
                        Text("単ページ").tag(ViewModePreference.single)
                        Text("見開き").tag(ViewModePreference.spread)
                    }
                    .pickerStyle(.segmented)
                }

                Text("自動モードでは、ウィンドウの縦横比に応じて表示モードを自動選択します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @available(macOS 13.0, *)
    private var slideshowSection: some View {
        GroupBox(label: sectionLabel("スライドショー", systemImage: "play.rectangle")) {
            VStack(alignment: .leading, spacing: 8) {
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
                Text("コンテキストメニューからスライドショーを開始し、この間隔で自動ページ送りします")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var windowSection: some View {
        GroupBox(label: sectionLabel("ウィンドウ設定", systemImage: "macwindow")) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("ウィンドウサイズ・位置を復元", isOn: Binding(
                    get: { settings.restoreWindowFrameEnabled },
                    set: { settings.restoreWindowFrameEnabled = $0 }
                ))
                .toggleStyle(.switch)

                if settings.savedWindowFrameString != nil {
                    Button("保存されたサイズ情報をリセット") {
                        settings.savedWindowFrameString = nil
                    }
                    .foregroundColor(.red)
                }
                Text("有効にすると、前回のプレビューウィンドウのサイズと位置で次回開きます")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers
    @ViewBuilder
    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.headline)
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        PreviewSettingsView()
    } else {
        // Fallback on earlier versions
    }
}

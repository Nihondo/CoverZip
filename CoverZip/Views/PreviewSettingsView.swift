//
//  PreviewSettingsView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/08/26.
//

import SwiftUI

@available(macOS 12.0, *)
@available(macOS 12.0, *)
struct PreviewSettingsView: View {
    @StateObject private var settings = AppSettingsWriter.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                readingDirectionSection
                displayModeSection
                uiSettingsSection
                slideshowSection
                windowSection
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 500)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("読み方向")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("右綴じ（日本のコミック）", isOn: Binding(
                    get: { settings.isRightToLeftReading },
                    set: { settings.isRightToLeftReading = $0 }
                ))
                
                Text("右綴じの場合、左クリックで次ページ、右クリックで前ページに移動します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var displayModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("表示モード")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("表紙を常に単ページ表示", isOn: Binding(
                    get: { settings.alwaysSinglePageForCover },
                    set: { settings.alwaysSinglePageForCover = $0 }
                ))
                
                HStack {
                    Text("デフォルト表示モード:")
                    Picker("", selection: Binding(
                        get: { settings.defaultViewMode },
                        set: { settings.defaultViewMode = $0 }
                    )) {
                        Text("自動").tag(AppSettingsWriter.ViewModePreference.auto)
                        Text("単ページ").tag(AppSettingsWriter.ViewModePreference.single)
                        Text("見開き").tag(AppSettingsWriter.ViewModePreference.spread)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Text("自動モードでは、ウィンドウの縦横比に応じて表示モードを自動選択します")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @available(macOS 12.0, *)
    @available(macOS 12.0, *)
    private var uiSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ユーザーインターフェイス")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("スライダー表示の最小幅:")
                    Spacer()
                    if #available(macOS 12.0, *) {
                        Text("\(Int(settings.sliderVisibilityWidthThreshold))px")
                            .monospacedDigit()
                    } else {
                        // Fallback on earlier versions
                    };if #available(macOS 12.0, *) {
                        Text("\(Int(settings.sliderVisibilityWidthThreshold))px")
                            .monospacedDigit()
                    } else {
                        // Fallback on earlier versions
                    }
                }
                
                Slider(
                    value: Binding(
                        get: { settings.sliderVisibilityWidthThreshold },
                        set: { settings.sliderVisibilityWidthThreshold = $0 }
                    ),
                    in: 300...800,
                    step: 50
                )
                
                Text("この幅未満でプレビューが表示される場合、ページスライダーは非表示になります")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var slideshowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("スライドショー")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("スライドショー機能を有効化", isOn: Binding(
                    get: { settings.slideshowEnabled },
                    set: { settings.slideshowEnabled = $0 }
                ))
                
                if settings.slideshowEnabled {
                    HStack {
                        Text("表示間隔:")
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
                }
                
                Text("コンテキストメニューからスライドショーを開始できます")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ウィンドウ設定")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("ウィンドウサイズ・位置を復元", isOn: Binding(
                    get: { settings.restoreWindowFrameEnabled },
                    set: { settings.restoreWindowFrameEnabled = $0 }
                ))
                
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
        }
    }
}

#Preview {
    if #available(macOS 12.0, *) {
        PreviewSettingsView()
    } else {
        // Fallback on earlier versions
    }
}

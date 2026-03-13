//
//  PreviewSettingsView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/08/26.
//

import SwiftUI

struct PreviewSettingsView: View {
    @ObservedObject private var settings = AppSettingsWriter.shared

    var body: some View {
        Form {
            Section {
                TrailingSegmentedPickerRow(
                    title: CZLocalized.string("settings.display.default_direction", defaultValue: "Default Reading Direction")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.isRightToLeftReading },
                        set: { settings.isRightToLeftReading = $0 }
                    )) {
                        Text(CZLocalized.string("settings.display.direction.rtl", defaultValue: "Right to Left")).tag(true)
                        Text(CZLocalized.string("settings.display.direction.ltr", defaultValue: "Left to Right")).tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                TrailingSegmentedPickerRow(
                    title: CZLocalized.string("settings.display.default_view_mode", defaultValue: "Default View Mode")
                ) {
                    Picker("", selection: Binding(
                        get: { settings.defaultViewMode },
                        set: { settings.defaultViewMode = $0 }
                    )) {
                        Text(CZLocalized.string("settings.display.mode.auto", defaultValue: "Auto")).tag(ViewModePreference.auto)
                        Text(CZLocalized.string("settings.display.mode.single", defaultValue: "Single Page")).tag(ViewModePreference.single)
                        Text(CZLocalized.string("settings.display.mode.spread", defaultValue: "Spread")).tag(ViewModePreference.spread)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                Toggle(CZLocalized.string("settings.display.cover_always_single", defaultValue: "Always show cover as single page"), isOn: Binding(
                    get: { settings.alwaysSinglePageForCover },
                    set: { settings.alwaysSinglePageForCover = $0 }
                ))

                Toggle(CZLocalized.string("settings.display.thumbnail_on_open", defaultValue: "Show thumbnail list when opening documents"), isOn: Binding(
                    get: { settings.isThumbnailStripVisible },
                    set: { settings.isThumbnailStripVisible = $0 }
                ))

                Toggle(CZLocalized.string("settings.display.page_transition", defaultValue: "Enable page transition animation"), isOn: Binding(
                    get: { settings.pageTransitionEnabled },
                    set: { settings.pageTransitionEnabled = $0 }
                ))
            } header: {
                Label(CZLocalized.string("settings.display.section", defaultValue: "Display"), systemImage: "rectangle.split.2x1")
            }

            Section {
                LabeledContent(CZLocalized.string("settings.decode_cache.policy_label", defaultValue: "Policy:")) {
                    Picker("", selection: Binding(
                        get: { settings.imageDecodeCachePolicy },
                        set: { settings.imageDecodeCachePolicy = $0 }
                    )) {
                        Text(CZLocalized.string("settings.decode_cache.policy.no_cache", defaultValue: "No cache")).tag(CZImageDecodeCachePolicy.noCache)
                        Text(CZLocalized.string("settings.decode_cache.policy.deferred", defaultValue: "Deferred (Recommended)")).tag(CZImageDecodeCachePolicy.deferred)
                        Text(CZLocalized.string("settings.decode_cache.policy.immediate", defaultValue: "Immediate (Fastest / More Memory)")).tag(CZImageDecodeCachePolicy.immediate)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            } header: {
                Label(CZLocalized.string("settings.decode_cache.section", defaultValue: "Image Decode Cache"), systemImage: "memorychip")
            } footer: {
                Text(CZLocalized.string(
                    "settings.decode_cache.footer",
                    defaultValue: "Deferred decodes only on first display, then avoids re-decoding for smoother rendering."
                ))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TrailingSegmentedPickerRow<PickerContent: View>: View {
    let title: String
    @ViewBuilder let pickerContent: () -> PickerContent

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .fixedSize()
            Spacer(minLength: 0)
            pickerContent()
                .fixedSize()
        }
    }
}

#Preview {
    PreviewSettingsView()
}

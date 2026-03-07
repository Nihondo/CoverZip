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
                Picker(CZLocalized.string("settings.display.default_direction", defaultValue: "Default Reading Direction"), selection: Binding(
                    get: { settings.isRightToLeftReading },
                    set: { settings.isRightToLeftReading = $0 }
                )) {
                    Text(CZLocalized.string("settings.display.direction.rtl", defaultValue: "Right to Left")).tag(true)
                    Text(CZLocalized.string("settings.display.direction.ltr", defaultValue: "Left to Right")).tag(false)
                }
                .pickerStyle(.segmented)

                Picker(CZLocalized.string("settings.display.default_view_mode", defaultValue: "Default View Mode"), selection: Binding(
                    get: { settings.defaultViewMode },
                    set: { settings.defaultViewMode = $0 }
                )) {
                    Text(CZLocalized.string("settings.display.mode.auto", defaultValue: "Auto")).tag(ViewModePreference.auto)
                    Text(CZLocalized.string("settings.display.mode.single", defaultValue: "Single Page")).tag(ViewModePreference.single)
                    Text(CZLocalized.string("settings.display.mode.spread", defaultValue: "Spread")).tag(ViewModePreference.spread)
                }
                .pickerStyle(.segmented)

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
                HStack {
                    Text(CZLocalized.string("settings.slideshow.interval_label", defaultValue: "Page interval:"))
                    Spacer()
                    Text(CZLocalized.formatted(
                        "settings.slideshow.interval_value_format",
                        defaultValue: "%.1f sec",
                        settings.slideshowInterval
                    ))
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
                Label(CZLocalized.string("settings.slideshow.section", defaultValue: "Slideshow"), systemImage: "play.rectangle")
            } footer: {
                Text(CZLocalized.string(
                    "settings.slideshow.footer",
                    defaultValue: "Start slideshow from the context menu; pages advance automatically at this interval."
                ))
            }

            Section {
                Toggle(CZLocalized.string("settings.window.restore_frame", defaultValue: "Restore window size and position"), isOn: Binding(
                    get: { settings.restoreWindowFrameEnabled },
                    set: { settings.restoreWindowFrameEnabled = $0 }
                ))

                if settings.savedWindowFrameString != nil {
                    Button(CZLocalized.string("settings.window.reset_saved_frame", defaultValue: "Reset saved window frame"), role: .destructive) {
                        settings.savedWindowFrameString = nil
                    }
                }
            } header: {
                Label(CZLocalized.string("settings.window.section", defaultValue: "Window"), systemImage: "macwindow")
            } footer: {
                Text(CZLocalized.string(
                    "settings.window.footer",
                    defaultValue: "When enabled, the next preview opens with the previous window size and position."
                ))
            }

            Section {
                Picker(CZLocalized.string("settings.decode_cache.policy_label", defaultValue: "Policy:"), selection: Binding(
                    get: { settings.imageDecodeCachePolicy },
                    set: { settings.imageDecodeCachePolicy = $0 }
                )) {
                    Text(CZLocalized.string("settings.decode_cache.policy.no_cache", defaultValue: "No cache")).tag(CZImageDecodeCachePolicy.noCache)
                    Text(CZLocalized.string("settings.decode_cache.policy.deferred", defaultValue: "Deferred (Recommended)")).tag(CZImageDecodeCachePolicy.deferred)
                    Text(CZLocalized.string("settings.decode_cache.policy.immediate", defaultValue: "Immediate (Fastest / More Memory)")).tag(CZImageDecodeCachePolicy.immediate)
                }
                .pickerStyle(.segmented)
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

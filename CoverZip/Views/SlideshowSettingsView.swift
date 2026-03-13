//
//  SlideshowSettingsView.swift
//  CoverZip
//
//  Created by Codex on 2026/03/13.
//

import SwiftUI

struct SlideshowSettingsView: View {
    @ObservedObject private var settings = AppSettingsWriter.shared

    var body: some View {
        Form {
            Section {
                LabeledContent(CZLocalized.string("settings.slideshow.interval_label", defaultValue: "Page interval:")) {
                    Text(
                        CZLocalized.formatted(
                            "settings.slideshow.interval_value_format",
                            defaultValue: "%.1f sec",
                            settings.slideshowInterval
                        )
                    )
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
                Text(
                    CZLocalized.string(
                        "settings.slideshow.footer",
                        defaultValue: "Start slideshow from the context menu; pages advance automatically at this interval."
                    )
                )
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    SlideshowSettingsView()
}

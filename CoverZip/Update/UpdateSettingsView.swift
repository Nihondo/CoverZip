// MARK: - UpdateSettingsView.swift
// Sparkleによるアップデート状態と設定を表示する。

import SwiftUI

/// アップデート設定タブのUI。
struct UpdateSettingsView: View {

    let releasesURL: URL

    @ObservedObject private var updateController = AppUpdateController.shared

    var body: some View {
        Form {
            Section {
                currentVersionRow
                lastCheckedRow
            }

            Section {
                checkNowButton
                automaticChecksToggle
            }

            Section {
                releasesLink
            }
        }
        .formStyle(.grouped)
        .navigationTitle(CZLocalized.string("app.tab.update", defaultValue: "Update"))
    }

    // MARK: - Rows

    private var currentVersionRow: some View {
        LabeledContent(CZLocalized.string("update.current_version", defaultValue: "Current Version")) {
            Text(versionText)
                .foregroundStyle(.secondary)
        }
    }

    private var lastCheckedRow: some View {
        LabeledContent(CZLocalized.string("update.last_checked", defaultValue: "Last Checked")) {
            Text(lastCheckedText)
                .foregroundStyle(.secondary)
        }
    }

    private var checkNowButton: some View {
        Button(CZLocalized.string("update.check_now", defaultValue: "Check Now")) {
            updateController.checkForUpdates()
        }
        .disabled(!updateController.canCheckForUpdates)
    }

    private var automaticChecksToggle: some View {
        Toggle(
            CZLocalized.string("update.automatic_checks", defaultValue: "Check for updates automatically"),
            isOn: Binding(
                get: { updateController.isAutomaticCheckEnabled },
                set: { updateController.setAutomaticCheckEnabled($0) }
            )
        )
    }

    private var releasesLink: some View {
        Link(destination: releasesURL) {
            HStack {
                Text(CZLocalized.string("update.releases_page", defaultValue: "Open Releases Page"))
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }

    private var lastCheckedText: String {
        guard let date = updateController.lastUpdateCheckDate else {
            return CZLocalized.string("update.never_checked", defaultValue: "Never")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

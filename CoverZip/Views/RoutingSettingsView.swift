//
//  RoutingSettingsView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/08/26.
//

import SwiftUI
import AppKit
import CoreServices
import UniformTypeIdentifiers

// MARK: - 列幅定数

private enum ColumnWidth {
    static let typePicker: CGFloat = 115
    static let matchMode: CGFloat = 155
    static let keywordField: CGFloat = 120
    static let applicationPicker: CGFloat = 200
    static let deleteButton: CGFloat = 28
}

// MARK: - RoutingSettingsView 本体

struct RoutingSettingsView: View {
    private let zipContentTypeIdentifiers = ["public.zip-archive", "com.pkware.zip-archive"]
    private let archiveUtilityBundleIdentifier = "com.apple.archiveutility"

    @State private var settings: KeywordSettings = KeywordSettings.load()
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isDefaultHandler = false
    @State private var currentDefaultAppName = ""

    /// 全ルール＋デフォルトで使用中のアプリ一覧（重複排除・順序保持）
    private var usedApplications: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for app in settings.rules.map(\.application) + [settings.defaultApplication] where !app.isEmpty && !seen.contains(app) {
            seen.insert(app)
            result.append(app)
        }
        return result
    }

    var body: some View {
        Form {
            fileAssociationSection

            Section {
                if settings.rules.isEmpty {
                    emptyRulesView
                } else {
                    columnHeaderView
                        .moveDisabled(true)
                        .listRowBackground(Color(NSColor.controlBackgroundColor).opacity(0.5))

                    ForEach($settings.rules) { $rule in
                        RuleRowView(
                            rule: $rule,
                            usedApplications: usedApplications,
                            onDelete: { deleteRule(rule) },
                            onChange: saveCurrentSettings
                        )
                    }
                    .onMove(perform: moveRules)
                }

                Button(action: addNewRule) {
                    Label(CZLocalized.string("routing.rules.add", defaultValue: "New Rule"), systemImage: "plus")
                }
            } header: {
                Label(CZLocalized.string("routing.rules.section", defaultValue: "Rules"), systemImage: "list.bullet")
            } footer: {
                Text(CZLocalized.string(
                    "routing.rules.footer",
                    defaultValue: "Rules are evaluated from top to bottom, and the first match is applied."
                ))
            }

            Section {
                defaultAppRow
            } header: {
                Label(CZLocalized.string("routing.default.section", defaultValue: "Default Application"), systemImage: "app")
            } footer: {
                Text(CZLocalized.string(
                    "routing.default.footer",
                    defaultValue: "Used when no rule matches."
                ))
            }

        }
        .formStyle(.grouped)
        .frame(minWidth: 760, minHeight: 480)
        .alert(CZLocalized.string("routing.alert.title", defaultValue: "Notice"), isPresented: $showingAlert) {
            Button(CZLocalized.string("common.ok", defaultValue: "OK"), role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear { refreshDefaultHandlerStatus() }
    }

    // MARK: - ファイル関連付けセクション

    private var fileAssociationSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDefaultHandler
                        ? CZLocalized.string("routing.association.status.is_default", defaultValue: "CoverZip is the default app for ZIP files")
                        : CZLocalized.string("routing.association.status.is_not_default", defaultValue: "CoverZip is not the default app for ZIP files")
                    )
                    if !currentDefaultAppName.isEmpty && !isDefaultHandler {
                        Text(CZLocalized.formatted(
                            "routing.association.current_default_format",
                            defaultValue: "Current default: %@",
                            currentDefaultAppName
                        ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(isDefaultHandler
                       ? CZLocalized.string("routing.association.action.unset_default", defaultValue: "Unset Default")
                       : CZLocalized.string("routing.association.action.set_default", defaultValue: "Set as Default")) {
                    toggleDefaultHandler()
                }
            }
        } header: {
            Label(CZLocalized.string("routing.association.section", defaultValue: "ZIP File Association"), systemImage: "link")
        }
    }

    // MARK: - 既定アプリ行

    private var defaultAppRow: some View {
        HStack {
            Text(CZLocalized.string("routing.default.label", defaultValue: "Default"))
                .foregroundColor(.secondary)
            Spacer()
            Text("→")
                .foregroundColor(.secondary)
            AppPickerMenu(
                application: $settings.defaultApplication,
                usedApplications: usedApplications,
                onChange: saveCurrentSettings
            )
        }
    }

    // MARK: - ルール表示

    private var emptyRulesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(CZLocalized.string("routing.rules.empty.title", defaultValue: "No Rules"))
                .foregroundColor(.secondary)
            Text(CZLocalized.string("routing.rules.empty.subtitle", defaultValue: "Click \"New Rule\" to add one."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var columnHeaderView: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 20)
            Text(CZLocalized.string("routing.rules.header.target", defaultValue: "Target"))
                .frame(width: ColumnWidth.typePicker, alignment: .leading)
            Text(CZLocalized.string("routing.rules.header.condition", defaultValue: "Condition"))
                .frame(width: ColumnWidth.matchMode, alignment: .leading)
            Text(CZLocalized.string("routing.rules.header.keyword", defaultValue: "Keyword"))
                .frame(width: ColumnWidth.keywordField, alignment: .leading)
            Text(CZLocalized.string("routing.rules.header.application", defaultValue: "Application"))
                .frame(width: ColumnWidth.applicationPicker, alignment: .leading)
            Spacer().frame(width: ColumnWidth.deleteButton)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
    }

    // MARK: - 補助メソッド

    private func addNewRule() {
        settings.rules.append(KeywordRule(keyword: "", type: .filename, application: "internal", matchMode: .contains))
        saveCurrentSettings()
    }

    private func deleteRule(_ rule: KeywordRule) {
        settings.rules.removeAll { $0.id == rule.id }
        saveCurrentSettings()
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        settings.rules.move(fromOffsets: source, toOffset: destination)
        saveCurrentSettings()
    }

    private func saveCurrentSettings() {
        if !SettingsFileManager.saveSettings(settings) {
            NSLog("ルーティング設定の保存に失敗しました")
        }
    }

    // MARK: - ファイル関連付け

    private func refreshDefaultHandlerStatus() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        if #available(macOS 12.0, *), let appURL = NSWorkspace.shared.urlForApplication(toOpen: .zip),
           let handlerID = Bundle(url: appURL)?.bundleIdentifier {
            updateDefaultHandlerState(handlerID: handlerID, bundleID: bundleID)
            return
        }

        for contentTypeIdentifier in zipContentTypeIdentifiers {
            guard let result = LSCopyDefaultRoleHandlerForContentType(contentTypeIdentifier as CFString, .viewer) else { continue }
            let handlerID = result.takeRetainedValue() as String
            updateDefaultHandlerState(handlerID: handlerID, bundleID: bundleID)
            return
        }

        isDefaultHandler = false
        currentDefaultAppName = ""
    }

    private func toggleDefaultHandler() {
        if isDefaultHandler {
            guard let archiveUtilityURL = resolveArchiveUtilityURL() else {
                alertMessage = CZLocalized.string(
                    "routing.alert.archive_utility_not_found",
                    defaultValue: "Could not unset default because Archive Utility was not found."
                )
                showingAlert = true
                return
            }
            setDefaultHandler(to: archiveUtilityURL)
        } else {
            setDefaultHandler(to: Bundle.main.bundleURL)
        }
    }

    private func setDefaultHandler(to appURL: URL) {
        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
            alertMessage = CZLocalized.string(
                "routing.alert.bundle_id_failed",
                defaultValue: "Failed to get application identifier."
            )
            showingAlert = true
            return
        }

        LSRegisterURL(appURL as CFURL, true)

        if #available(macOS 12.0, *) {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: .zip) { error in
                DispatchQueue.main.async {
                    if let error {
                        let fallbackResult = self.applyLaunchServicesDefaultHandler(bundleID: bundleID)
                        if !fallbackResult.isSuccess {
                            self.alertMessage = self.makeDefaultHandlerErrorMessage(error: error as NSError, statusDetails: fallbackResult.statusDetails)
                            self.showingAlert = true
                        }
                    }
                    self.refreshDefaultHandlerStatus()
                }
            }
            return
        }

        let fallbackResult = applyLaunchServicesDefaultHandler(bundleID: bundleID)
        if !fallbackResult.isSuccess {
            alertMessage = CZLocalized.formatted(
                "routing.alert.ls_change_failed_status_format",
                defaultValue: "Failed to change ZIP file association (%@)",
                fallbackResult.statusDetails.joined(separator: ", ")
            )
            showingAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            refreshDefaultHandlerStatus()
        }
    }

    private func applyLaunchServicesDefaultHandler(bundleID: String) -> (isSuccess: Bool, statusDetails: [String]) {
        var hasSuccess = false
        var statusDetails: [String] = []
        for contentTypeIdentifier in zipContentTypeIdentifiers {
            let viewerStatus = LSSetDefaultRoleHandlerForContentType(contentTypeIdentifier as CFString, .viewer, bundleID as CFString)
            let allRolesStatus = LSSetDefaultRoleHandlerForContentType(contentTypeIdentifier as CFString, .all, bundleID as CFString)
            statusDetails.append("\(contentTypeIdentifier)(viewer=\(viewerStatus),all=\(allRolesStatus))")
            if viewerStatus == noErr || allRolesStatus == noErr {
                hasSuccess = true
            }
        }
        return (hasSuccess, statusDetails)
    }

    private func makeDefaultHandlerErrorMessage(error: NSError, statusDetails: [String]) -> String {
        let statusText = statusDetails.joined(separator: ", ")
        return CZLocalized.formatted(
            "routing.alert.ls_change_failed_detail_format",
            defaultValue: "Failed to change ZIP file association: %@ [%@:%d] (%@)",
            error.localizedDescription,
            error.domain,
            error.code,
            statusText
        )
    }

    private func updateDefaultHandlerState(handlerID: String, bundleID: String) {
        isDefaultHandler = (handlerID == bundleID)
        if isDefaultHandler {
            currentDefaultAppName = ""
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: handlerID) {
            currentDefaultAppName = ApplicationPicker.displayName(for: url)
            return
        }
        currentDefaultAppName = handlerID
    }

    private func resolveArchiveUtilityURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: archiveUtilityBundleIdentifier) {
            return url
        }
        let fallbackURL = URL(fileURLWithPath: "/System/Library/CoreServices/Applications/Archive Utility.app")
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }
        return nil
    }
}

// MARK: - ルール行ビュー

struct RuleRowView: View {
    @Binding var rule: KeywordRule
    let usedApplications: [String]
    let onDelete: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Picker("", selection: $rule.type) {
                    ForEach(KeywordType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .onChange(of: rule.type) { _ in onChange() }
                Spacer()
            }
            .frame(width: ColumnWidth.typePicker)

            HStack(spacing: 0) {
                Picker("", selection: $rule.matchMode) {
                    ForEach(MatchMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .onChange(of: rule.matchMode) { _ in onChange() }
                Spacer()
            }
            .frame(width: ColumnWidth.matchMode)

            LeadingTextField(text: $rule.keyword, onChange: onChange)
                .frame(width: ColumnWidth.keywordField, height: 22)

            AppPickerMenu(
                application: $rule.application,
                usedApplications: usedApplications,
                onChange: onChange
            )
            .frame(width: ColumnWidth.applicationPicker, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help(CZLocalized.string("routing.help.delete", defaultValue: "Delete"))
            .frame(width: ColumnWidth.deleteButton)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - アプリ選択メニュー

struct AppPickerMenu: View {
    @Binding var application: String
    let usedApplications: [String]
    let onChange: () -> Void

    private var displayName: String { ApplicationPicker.displayName(for: application) }
    private var otherApps: [String] { usedApplications.filter { $0 != "internal" } }

    var body: some View {
        Menu {
            Button {
                application = "internal"
                onChange()
            } label: {
                menuItemLabel(app: "internal", isSelected: application == "internal")
            }

            if !otherApps.isEmpty {
                Divider()
                ForEach(otherApps, id: \.self) { app in
                    Button {
                        application = app
                        onChange()
                    } label: {
                        menuItemLabel(app: app, isSelected: application == app)
                    }
                }
            }

            Divider()

            Button(CZLocalized.string("routing.app_picker.choose_app", defaultValue: "Choose App...")) {
                ApplicationPicker.pickApplication { url in
                    if let url = url {
                        application = url.path
                        onChange()
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                appIconView(for: application, size: 16)
                Text(displayName).lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private func menuItemLabel(app: String, isSelected: Bool) -> some View {
        HStack {
            appIconView(for: app, size: 16)
            Text(ApplicationPicker.displayName(for: app))
            if isSelected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private func sizedIcon(for app: String, size: CGFloat) -> NSImage? {
        guard let icon = ApplicationPicker.icon(for: app) else { return nil }
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    @ViewBuilder
    private func appIconView(for app: String, size: CGFloat) -> some View {
        if let icon = sizedIcon(for: app, size: size) {
            Image(nsImage: icon)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app")
                .frame(width: size, height: size)
        }
    }
}

// MARK: - 左寄せ TextField（NSViewRepresentable）

/// macOS Form の右揃え強制を回避し、テキストを左揃えで表示する TextField
private struct LeadingTextField: NSViewRepresentable {
    @Binding var text: String
    let onChange: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.drawsBackground = true
        field.alignment = .left
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.alignment = .left
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LeadingTextField
        init(parent: LeadingTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onChange()
        }
    }
}

// MARK: - プレビュー

#Preview {
    RoutingSettingsView()
}

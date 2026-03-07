//
//  RoutingSettingsView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/08/26.
//

import SwiftUI
import AppKit
import CoreServices

// MARK: - Column Width Constants

private enum ColumnWidth {
    static let typePicker: CGFloat = 115
    static let matchMode: CGFloat = 155
    static let deleteButton: CGFloat = 28
}

// MARK: - RoutingSettingsView

struct RoutingSettingsView: View {
    @State private var settings: KeywordSettings = SettingsFileManager.loadSettings()
    @State private var hasUnsavedChanges = false
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
                            onChange: { hasUnsavedChanges = true }
                        )
                    }
                    .onMove(perform: moveRules)
                }

                Button(action: addNewRule) {
                    Label("新規ルール", systemImage: "plus")
                }
            } header: {
                Label("ルール一覧", systemImage: "list.bullet")
            } footer: {
                Text("ルールは上から順に評価され、最初にマッチしたルールが適用されます。")
            }

            Section {
                defaultAppRow
            } header: {
                Label("デフォルトアプリケーション", systemImage: "app")
            } footer: {
                Text("ルールにマッチしない場合に使用されます。")
            }

            Section {
                HStack {
                    Button("保存") { saveSettings() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasUnsavedChanges)
                    Button("リセット") { resetSettings() }
                        .disabled(!hasUnsavedChanges)
                    Spacer()
                    Button("JSONファイルを編集") {
                        let _ = SettingsFileManager.openSettingsFileInExternalEditor()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 760, minHeight: 480)
        .alert("通知", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear { refreshDefaultHandlerStatus() }
    }

    // MARK: - File Association Section

    private var fileAssociationSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDefaultHandler
                        ? "CoverZipがZIPファイルのデフォルトアプリです"
                        : "CoverZipはZIPファイルのデフォルトアプリではありません"
                    )
                    if !currentDefaultAppName.isEmpty && !isDefaultHandler {
                        Text("現在のデフォルト: \(currentDefaultAppName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(isDefaultHandler ? "デフォルトを解除" : "デフォルトに設定") {
                    toggleDefaultHandler()
                }
            }
        } header: {
            Label("ZIPファイルの関連付け", systemImage: "link")
        }
    }

    // MARK: - Default App Row

    private var defaultAppRow: some View {
        HStack {
            Text("デフォルト")
                .foregroundColor(.secondary)
            Spacer()
            Text("→")
                .foregroundColor(.secondary)
            AppPickerMenu(
                application: $settings.defaultApplication,
                usedApplications: usedApplications,
                onChange: { hasUnsavedChanges = true }
            )
        }
    }

    // MARK: - Rules Views

    private var emptyRulesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("ルールがありません")
                .foregroundColor(.secondary)
            Text("「新規ルール」ボタンをクリックして追加してください")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var columnHeaderView: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 20)
            Text("対象")
                .frame(width: ColumnWidth.typePicker, alignment: .leading)
            Text("条件")
                .frame(width: ColumnWidth.matchMode, alignment: .leading)
            Text("キーワード")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("アプリケーション")
                .frame(minWidth: 140, alignment: .leading)
            Spacer().frame(width: ColumnWidth.deleteButton)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
    }

    // MARK: - Helper Methods

    private func addNewRule() {
        settings.rules.append(KeywordRule(keyword: "", type: .filename, application: "internal", matchMode: .contains))
        hasUnsavedChanges = true
    }

    private func deleteRule(_ rule: KeywordRule) {
        settings.rules.removeAll { $0.id == rule.id }
        hasUnsavedChanges = true
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        settings.rules.move(fromOffsets: source, toOffset: destination)
        hasUnsavedChanges = true
    }

    private func saveSettings() {
        if SettingsFileManager.saveSettings(settings) {
            hasUnsavedChanges = false
            alertMessage = "設定を保存しました"
            showingAlert = true
        } else {
            alertMessage = "設定の保存に失敗しました"
            showingAlert = true
        }
    }

    private func resetSettings() {
        settings = SettingsFileManager.loadSettings()
        hasUnsavedChanges = false
    }

    // MARK: - File Association

    private func refreshDefaultHandlerStatus() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        guard let result = LSCopyDefaultRoleHandlerForContentType("public.zip-archive" as CFString, .all) else { return }
        let handlerID = result.takeRetainedValue() as String
        isDefaultHandler = (handlerID == bundleID)
        if !isDefaultHandler, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: handlerID) {
            currentDefaultAppName = ApplicationPicker.displayName(for: url)
        }
    }

    private func toggleDefaultHandler() {
        if isDefaultHandler {
            let archivePath = "/System/Library/CoreServices/Applications/Archive Utility.app"
            if let archiveBundleID = Bundle(path: archivePath)?.bundleIdentifier {
                LSSetDefaultRoleHandlerForContentType("public.zip-archive" as CFString, .all, archiveBundleID as CFString)
            }
        } else if let bundleID = Bundle.main.bundleIdentifier {
            LSSetDefaultRoleHandlerForContentType("public.zip-archive" as CFString, .all, bundleID as CFString)
        }
        refreshDefaultHandlerStatus()
    }
}

// MARK: - Rule Row View

struct RuleRowView: View {
    @Binding var rule: KeywordRule
    let usedApplications: [String]
    let onDelete: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

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
                .frame(minWidth: 80, maxWidth: .infinity, minHeight: 22)

            AppPickerMenu(
                application: $rule.application,
                usedApplications: usedApplications,
                onChange: onChange
            )
            .frame(minWidth: 140)

            Button(action: onDelete) {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("削除")
            .frame(width: ColumnWidth.deleteButton)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - App Picker Menu

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

            Button("アプリを選択...") {
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

// MARK: - Leading-aligned TextField (NSViewRepresentable)

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

// MARK: - Preview

#Preview {
    RoutingSettingsView()
}

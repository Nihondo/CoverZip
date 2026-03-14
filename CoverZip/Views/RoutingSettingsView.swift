//
//  RoutingSettingsView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/08/26.
//

import SwiftUI
import AppKit
import CoreServices

private enum ColumnWidth {
    static let dragHandle: CGFloat = 20
    static let target: CGFloat = 120
    static let condition: CGFloat = 120
    static let keyword: CGFloat = 100
    static let application: CGFloat = 100
    static let deleteButton: CGFloat = 20
}

private struct RoutingTableRow: Identifiable, Hashable {
    let id: String
    let ruleID: UUID?

    var isDefault: Bool { ruleID == nil }

    static let fallback = RoutingTableRow(id: "default", ruleID: nil)

    init(ruleID: UUID) {
        self.id = ruleID.uuidString
        self.ruleID = ruleID
    }

    private init(id: String, ruleID: UUID?) {
        self.id = id
        self.ruleID = ruleID
    }
}

struct RoutingSettingsView: View {
    private let zipContentTypeIdentifiers = ["public.zip-archive", "com.pkware.zip-archive"]
    private let archiveUtilityBundleIdentifier = "com.apple.archiveutility"

    @State private var settings: KeywordSettings = KeywordSettings.load()
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isDefaultHandler = false
    @State private var currentDefaultAppName = ""

    private var usedApplications: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for app in settings.rules.map(\.application) + [settings.defaultApplication] where !app.isEmpty && !seen.contains(app) {
            seen.insert(app)
            result.append(app)
        }
        return result
    }

    private var tableRows: [RoutingTableRow] {
        settings.rules.map { RoutingTableRow(ruleID: $0.id) } + [.fallback]
    }

    private var minimumTableHeight: CGFloat {
        let visibleRows = max(settings.rules.count + 1, 4)
        return CGFloat(visibleRows) * 44.0 + 28.0
    }

    var body: some View {
        Form {
            fileAssociationSection
            rulesSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 760, minHeight: 480)
        .alert(CZLocalized.string("routing.alert.title", defaultValue: "Notice"), isPresented: $showingAlert) {
            Button(CZLocalized.string("common.ok", defaultValue: "OK"), role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear { refreshDefaultHandlerStatus() }
    }

    private var fileAssociationSection: some View {
        Section {
            LabeledContent {
                Button(
                    isDefaultHandler
                    ? CZLocalized.string("routing.association.action.unset_default", defaultValue: "Unset Default")
                    : CZLocalized.string("routing.association.action.set_default", defaultValue: "Set as Default")
                ) {
                    toggleDefaultHandler()
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        isDefaultHandler
                        ? CZLocalized.string("routing.association.status.is_default", defaultValue: "CoverZip is the default app for ZIP files")
                        : CZLocalized.string("routing.association.status.is_not_default", defaultValue: "CoverZip is not the default app for ZIP files")
                    )

                    if !currentDefaultAppName.isEmpty && !isDefaultHandler {
                        Text(
                            CZLocalized.formatted(
                                "routing.association.current_default_format",
                                defaultValue: "Current default: %@",
                                currentDefaultAppName
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Label(CZLocalized.string("routing.association.section", defaultValue: "ZIP File Association"), systemImage: "link")
        }
    }

    private var rulesSection: some View {
        Section {
            if settings.rules.isEmpty {
                ContentUnavailableView(
                    CZLocalized.string("routing.rules.empty.title", defaultValue: "No Rules"),
                    systemImage: "list.bullet.rectangle",
                    description: Text(CZLocalized.string("routing.rules.empty.subtitle", defaultValue: "Click \"New Rule\" to add one."))
                )
            }

            routingTable
                .frame(minHeight: minimumTableHeight)

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
    }

    private var routingTable: some View {
        Table(of: RoutingTableRow.self) {
            TableColumn("") { row in
                dragHandleCell(for: row)
            }
            .width(ColumnWidth.dragHandle)

            TableColumn(CZLocalized.string("routing.rules.header.target", defaultValue: "Target")) { row in
                targetCell(for: row)
            }
            .width(ColumnWidth.target)

            TableColumn(CZLocalized.string("routing.rules.header.condition", defaultValue: "Condition")) { row in
                conditionCell(for: row)
            }
            .width(ColumnWidth.condition)

            TableColumn(CZLocalized.string("routing.rules.header.keyword", defaultValue: "Keyword")) { row in
                keywordCell(for: row)
            }
            .width(min: ColumnWidth.keyword)

            TableColumn(CZLocalized.string("routing.rules.header.application", defaultValue: "Application")) { row in
                applicationCell(for: row)
            }
            .width(min: ColumnWidth.application)

            TableColumn("") { row in
                deleteCell(for: row)
            }
            .width(ColumnWidth.deleteButton)
        } rows: {
            ForEach(tableRows) { row in
                TableRow(row)
            }
            .dropDestination(for: String.self) { destination, draggedRowIDs in
                moveDraggedRules(with: draggedRowIDs, to: destination)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func dragHandleCell(for row: RoutingTableRow) -> some View {
        if row.isDefault {
            EmptyView()
        } else {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .help(CZLocalized.string("routing.help.reorder", defaultValue: "Drag to reorder"))
                .onDrag {
                    NSItemProvider(object: row.id as NSString)
                }
        }
    }

    @ViewBuilder
    private func targetCell(for row: RoutingTableRow) -> some View {
        if let rule = binding(for: row) {
            Picker("", selection: rule.type) {
                ForEach(KeywordType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            .onChange(of: rule.wrappedValue.type) { saveCurrentSettings() }
        } else {
            Text(CZLocalized.string("routing.default.label", defaultValue: "Default"))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func conditionCell(for row: RoutingTableRow) -> some View {
        if let rule = binding(for: row) {
            Picker("", selection: rule.matchMode) {
                ForEach(MatchMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .onChange(of: rule.wrappedValue.matchMode) { saveCurrentSettings() }
        } else {
            Text("—")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func keywordCell(for row: RoutingTableRow) -> some View {
        if let keyword = keywordBinding(for: row) {
            TextField("", text: keyword)
                .textFieldStyle(.roundedBorder)
                .frame(height: 24)
        } else {
            Text("—")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func applicationCell(for row: RoutingTableRow) -> some View {
        if let rule = binding(for: row) {
            AppPickerMenu(
                application: rule.application,
                usedApplications: usedApplications,
                onChange: saveCurrentSettings
            )
        } else {
            AppPickerMenu(
                application: Binding(
                    get: { settings.defaultApplication },
                    set: { settings.defaultApplication = $0 }
                ),
                usedApplications: usedApplications,
                onChange: saveCurrentSettings
            )
        }
    }

    @ViewBuilder
    private func deleteCell(for row: RoutingTableRow) -> some View {
        if let ruleID = row.ruleID {
            Button(role: .destructive) {
                deleteRule(id: ruleID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(CZLocalized.string("routing.help.delete", defaultValue: "Delete"))
        } else {
            EmptyView()
        }
    }

    private func binding(for row: RoutingTableRow) -> Binding<KeywordRule>? {
        guard let ruleID = row.ruleID,
              let index = settings.rules.firstIndex(where: { $0.id == ruleID }) else {
            return nil
        }
        return $settings.rules[index]
    }

    private func keywordBinding(for row: RoutingTableRow) -> Binding<String>? {
        guard let rule = binding(for: row) else { return nil }
        return Binding(
            get: { rule.wrappedValue.keyword },
            set: { updatedKeyword in
                guard rule.wrappedValue.keyword != updatedKeyword else { return }
                rule.wrappedValue.keyword = updatedKeyword
                saveCurrentSettings()
            }
        )
    }

    private func addNewRule() {
        settings.rules.append(
            KeywordRule(keyword: "", type: .filename, application: "internal", matchMode: .contains)
        )
        saveCurrentSettings()
    }

    private func deleteRule(id: UUID) {
        settings.rules.removeAll { $0.id == id }
        saveCurrentSettings()
    }

    private func moveDraggedRules(with draggedRowIDs: [String], to destination: Int) {
        let sourceIndexes = IndexSet(
            draggedRowIDs.compactMap { rowID in
                settings.rules.firstIndex { $0.id.uuidString == rowID }
            }
        )

        guard !sourceIndexes.isEmpty else { return }

        let clampedDestination = min(destination, settings.rules.count)
        settings.rules.move(fromOffsets: sourceIndexes, toOffset: clampedDestination)
        saveCurrentSettings()
    }

    private func saveCurrentSettings() {
        if !SettingsFileManager.saveSettings(settings) {
            NSLog("ルーティング設定の保存に失敗しました")
        }
    }

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
                            self.alertMessage = self.makeDefaultHandlerErrorMessage(
                                error: error as NSError,
                                statusDetails: fallbackResult.statusDetails
                            )
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
                    if let url {
                        application = url.path
                        onChange()
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                appIconView(for: application, size: 16)
                Text(displayName)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview {
    RoutingSettingsView()
}

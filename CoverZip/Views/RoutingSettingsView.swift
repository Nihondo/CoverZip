//
//  RoutingSettingsView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/08/26.
//

import SwiftUI

struct RoutingSettingsView: View {
    @State private var settings: KeywordSettings = SettingsFileManager.loadSettings()
    @State private var hasUnsavedChanges = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            rulesSection
            defaultApplicationSection
            actionsSection
            Spacer()
        }
        .padding()
        .frame(minWidth: 700, minHeight: 500)
        .alert("通知", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ファイルルーティング設定")
                .font(.title2)
                .fontWeight(.semibold)
            Text("ZIPファイル名に基づいて適切なアプリケーションを自動起動します")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("ルールは上から順に適用されます。ドラッグして並び替えできます")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Rules Section

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ルール一覧")
                    .font(.headline)
                Spacer()
                Button(action: addNewRule) {
                    Label("新規ルール", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            if settings.rules.isEmpty {
                emptyRulesView
            } else {
                rulesTableView
            }
        }
    }

    private var emptyRulesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("ルールがありません")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("「新規ルール」ボタンをクリックして追加してください")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    private var rulesTableView: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("キーワード")
                    .frame(width: 150, alignment: .leading)
                Text("マッチ方式")
                    .frame(width: 130, alignment: .leading)
                Text("対象")
                    .frame(width: 100, alignment: .leading)
                Text("アプリケーション")
                    .frame(minWidth: 150, alignment: .leading)
                Spacer()
                Text("")
                    .frame(width: 30)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))

            Divider()

            // Rules List
            List {
                ForEach($settings.rules) { $rule in
                    RuleRowView(rule: $rule, onDelete: {
                        deleteRule(rule)
                    }, onChange: {
                        hasUnsavedChanges = true
                    })
                }
                .onMove(perform: moveRules)
            }
            .listStyle(.plain)
            .frame(minHeight: 200)
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Default Application Section

    private var defaultApplicationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("デフォルトアプリケーション")
                .font(.headline)
            HStack {
                Text("ルールにマッチしない場合:")
                    .font(.subheadline)
                TextField("アプリケーション名", text: $settings.defaultApplication)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                    .onChange(of: settings.defaultApplication) { _ in
                        hasUnsavedChanges = true
                    }
                Button("選択...") {
                    ApplicationPicker.pickApplication { appName in
                        if let appName = appName {
                            settings.defaultApplication = appName
                            hasUnsavedChanges = true
                        }
                    }
                }
            }
            Text("空欄の場合、システムのデフォルトアプリケーションで開きます")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button("保存") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasUnsavedChanges)

            Button("リセット") {
                resetSettings()
            }
            .disabled(!hasUnsavedChanges)

            Spacer()

            Button("JSONファイルを編集") {
                let _ = SettingsFileManager.openSettingsFileInExternalEditor()
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }

    // MARK: - Helper Methods

    private func addNewRule() {
        let newRule = KeywordRule(
            keyword: "新しいキーワード",
            type: .filename,
            application: "internal",
            matchMode: .contains
        )
        settings.rules.append(newRule)
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
}

// MARK: - Rule Row View

struct RuleRowView: View {
    @Binding var rule: KeywordRule
    let onDelete: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Keyword
            TextField("キーワード", text: $rule.keyword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                .onChange(of: rule.keyword) { _ in onChange() }

            // Match Mode
            Picker("", selection: $rule.matchMode) {
                ForEach(MatchMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .frame(width: 130)
            .onChange(of: rule.matchMode) { _ in onChange() }

            // Type
            Picker("", selection: $rule.type) {
                ForEach(KeywordType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .frame(width: 100)
            .onChange(of: rule.type) { _ in onChange() }

            // Application
            HStack(spacing: 4) {
                TextField("アプリ", text: $rule.application)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)
                    .onChange(of: rule.application) { _ in onChange() }

                Button(action: {
                    ApplicationPicker.pickApplication { appName in
                        if let appName = appName {
                            rule.application = appName
                            onChange()
                        }
                    }
                }) {
                    Image(systemName: "folder")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("アプリケーションを選択")
            }
            .frame(minWidth: 150)

            Spacer()

            // Delete Button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("削除")
            .frame(width: 30)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    RoutingSettingsView()
}
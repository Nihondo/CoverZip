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
        Form {
            Section {
                if settings.rules.isEmpty {
                    emptyRulesView
                } else {
                    rulesListView
                }

                HStack {
                    Button(action: addNewRule) {
                        Label("新規ルール", systemImage: "plus")
                    }
                    Spacer()
                }
            } header: {
                Label("ルール一覧", systemImage: "list.bullet")
            } footer: {
                Text("ZIPファイル名に基づいて適切なアプリケーションを自動起動します。ルールは上から順に適用されます。")
            }

            Section {
                HStack {
                    TextField("アプリケーション名", text: $settings.defaultApplication)
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
            } header: {
                Label("デフォルトアプリケーション", systemImage: "app")
            } footer: {
                Text("ルールにマッチしない場合に使用されます。空欄の場合はシステムのデフォルトアプリケーションで開きます。")
            }

            Section {
                HStack {
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
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 650, minHeight: 450)
        .alert("通知", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
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

    private var rulesListView: some View {
        ForEach($settings.rules) { $rule in
            RuleRowView(rule: $rule, onDelete: {
                deleteRule(rule)
            }, onChange: {
                hasUnsavedChanges = true
            })
        }
        .onMove(perform: moveRules)
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
        HStack(spacing: 8) {
            TextField("キーワード", text: $rule.keyword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
                .onChange(of: rule.keyword) { _ in onChange() }

            Picker("", selection: $rule.matchMode) {
                ForEach(MatchMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .frame(width: 120)
            .onChange(of: rule.matchMode) { _ in onChange() }

            Picker("", selection: $rule.type) {
                ForEach(KeywordType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .frame(width: 100)
            .onChange(of: rule.type) { _ in onChange() }

            HStack(spacing: 4) {
                TextField("アプリ", text: $rule.application)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 100)
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

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("削除")
        }
    }
}

// MARK: - Preview

#Preview {
    RoutingSettingsView()
}

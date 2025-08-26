//
//  RoutingSettingsView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/08/26.
//

import SwiftUI

struct RoutingSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            settingsFileSection
            Spacer()
        }
        .padding()
        .frame(minWidth: 450, minHeight: 300)
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ファイルルーティング設定")
                .font(.title2)
                .fontWeight(.semibold)
            Text("ZIPファイル名に基づいて適切なアプリケーションを自動起動します")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var settingsFileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("設定ファイル")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Button("設定ファイルを編集") {
                    let _ = SettingsFileManager.openSettingsFileInExternalEditor()
                }
                .controlSize(.large)
                
                Text("settings.json ファイルを外部エディタで編集します")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("設定例:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("""
{
  "keywords": {
    "コミック": {
      "type": "filename",
      "application": "YourComicViewer.app",
      "matchMode": "contains"
    },
    "backup_*": {
      "type": "filename", 
      "application": "Archive Utility.app",
      "matchMode": "wildcard"
    }
  },
  "default": "Archive Utility.app"
}
""")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                }
            }
        }
    }
}

#Preview {
    RoutingSettingsView()
}
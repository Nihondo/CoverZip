//
//  KeywordConfigView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/19.
//

import SwiftUI

/**
 * 簡素化されたキーワード設定画面
 */
struct KeywordConfigView: View {
    @State private var newKeyword = ""
    @State private var selectedApplication = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("キーワード設定")
                .font(.title2)
                .fontWeight(.bold)
                .padding()
            
            Text("現在このビューは実装中です")
                .foregroundColor(.secondary)
                .padding()
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    KeywordConfigView()
}
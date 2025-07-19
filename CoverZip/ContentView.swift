//
//  ContentView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/15.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Binding var document: CoverZipDocument

    var body: some View {
        VStack(spacing: 20) {
            Text("CoverZip")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()
            
            if let zipURL = document.zipFileURL {
                VStack(spacing: 10) {
                    Text("処理完了: \(zipURL.lastPathComponent)")
                        .font(.headline)
                    
                    if let launchResult = document.launchResult {
                        Text(AppLauncher.resultDescription(launchResult))
                            .foregroundColor(isSuccessResult(launchResult) ? .green : .orange)
                    }
                }
                .padding()
                .onAppear {
                    // 処理完了後にウィンドウを閉じる
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        NSApplication.shared.keyWindow?.close()
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("ZIPファイルを開いてください")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            Spacer()
        }
        .frame(minWidth: 300, minHeight: 200)
    }
    
    private func isSuccessResult(_ result: AppLaunchResult) -> Bool {
        if case .success = result {
            return true
        }
        return false
    }
}

#Preview {
    ContentView(document: .constant(CoverZipDocument()))
}
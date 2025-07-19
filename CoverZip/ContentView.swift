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
            Image(systemName: "doc.zipper")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("CoverZip")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("ZIPファイルルーティング")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(minWidth: 300, minHeight: 200)
    }
    
}

#Preview {
    ContentView(document: .constant(CoverZipDocument()))
}
//
//  ContentView.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/15.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: CoverZipDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(CoverZipDocument()))
}

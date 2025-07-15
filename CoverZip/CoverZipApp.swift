//
//  CoverZipApp.swift
//  CoverZip
//
//  Created by Nihondo on 2025/07/15.
//

import SwiftUI

@main
struct CoverZipApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: CoverZipDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}

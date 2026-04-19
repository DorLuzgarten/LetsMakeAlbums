//
//  LetsMakeAlbumsApp.swift
//  LetsMakeAlbums
//
//  Created by Dor Luzgarten on 15/04/2026.
//

import SwiftUI

@main
struct LetsMakeAlbumsApp: App {
    var body: some Scene {
        WindowGroup("Let's Make Albums") {
            ContentView()
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            // This app manages one library window; suppress File > New.
            CommandGroup(replacing: .newItem) { }
        }
    }
}

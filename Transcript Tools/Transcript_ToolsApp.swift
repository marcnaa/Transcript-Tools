//
//  Transcript_ToolsApp.swift
//  Transcript Tools
//
//  Created by Marc Noguera on 09/06/2026.
//

import SwiftUI

@main
struct Transcript_ToolsApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
        }

        Settings {
            SettingsView(controller: controller)
        }
    }
}

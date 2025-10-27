//
//  BerryApp.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-08-08.
//

import AppKit
import SwiftUI

@main
struct BerryApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @StateObject private var authService = AuthService()

  var body: some Scene {
    WindowGroup {
      if authService.isAuthenticated {
        ContentView(authService: authService)
          .onAppear {
            // Configure and position window collapsed when authenticated
            if let window = NSApplication.shared.windows.first {
              WindowManager.shared.configureWindow(window)
              WindowManager.shared.positionWindowCollapsed(window)
            }
          }
      } else {
        LoginView(authService: authService)
          .onAppear {
            // Center login window
            if let window = NSApplication.shared.windows.first {
              WindowManager.shared.configureLoginWindow(window)
              window.center()
            }
          }
      }
    }
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    print("App launched")
  }
}

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

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  static weak var shared: AppDelegate?
  var window: NSWindow?

  private var lastExpandedSize: NSSize?

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppDelegate.shared = self

    // Get the main window
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      if let window = NSApplication.shared.windows.first {
        print("This Window found")
        self.window = window
        self.configureWindow(window)
        self.positionWindowCollapsed(window)
      } else {
        print("This Window not found")
      }
    }
  }

  private func configureWindow(_ window: NSWindow) {
    // Configure window appearance for floating panel
    print("Configuring window")
    window.styleMask = [.borderless, .resizable]
    window.isMovableByWindowBackground = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
  }

  func positionWindowCollapsed(_ window: NSWindow) {
    if window.frame.width > 100 {
      lastExpandedSize = window.frame.size
    }

    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let collapsedWidth: CGFloat = 30
      let collapsedHeight: CGFloat = 80
      let xPosition = screenFrame.maxX - collapsedWidth * 0.8
      let yPosition = screenFrame.maxY - (screenFrame.height / 5) - collapsedHeight

      window.setFrame(
        NSRect(x: xPosition, y: yPosition, width: collapsedWidth, height: collapsedHeight),
        display: true,
        animate: true
      )
    }
  }

  func positionWindowExpanded(_ window: NSWindow) {
    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame

      let expandedWidth: CGFloat = lastExpandedSize?.width ?? 450
      let expandedHeight: CGFloat = lastExpandedSize?.height ?? 650

      let xPosition = screenFrame.maxX - expandedWidth
      let yPosition = screenFrame.maxY - (screenFrame.height / 5) - expandedHeight

      print("Expanded window position: \(xPosition), \(yPosition)")

      window.setFrame(
        NSRect(x: xPosition, y: yPosition, width: expandedWidth, height: expandedHeight),
        display: true,
        animate: true
      )
    }
  }
}

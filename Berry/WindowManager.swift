//
//  WindowManager.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-10-27.
//

import AppKit
import Combine

class WindowManager: ObservableObject {
  static let shared = WindowManager()
  private init() {}

  private var lastExpandedSize: NSSize?
  @Published var isExpanded: Bool = false

  func configureLoginWindow(_ window: NSWindow) {
    // Normal window for login screen
    print("Configuring login window")
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.styleMask.remove(.resizable)
    window.setContentSize(NSSize(width: 400, height: 500))
    window.isMovableByWindowBackground = true
    window.level = .normal
    window.backgroundColor = NSColor.windowBackgroundColor
    window.isOpaque = true
    window.hasShadow = true
  }

  func configureWindow(_ window: NSWindow) {
    // Configure window appearance for floating panel (for main app)
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
    print("Positioning window collapsed")
    // Capture size if we're actually collapsing from expanded state
    if isExpanded {
      print("Capturing expanded size")
      lastExpandedSize = window.frame.size
      isExpanded = false
    }

    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let collapsedWidth: CGFloat = 30
      let collapsedHeight: CGFloat = 80
      let xPosition = screenFrame.maxX - collapsedWidth * 0.8
      let yPosition = screenFrame.maxY - (screenFrame.height / 5) - collapsedHeight

      print(
        "Setting frame to: \(NSRect(x: xPosition, y: yPosition, width: collapsedWidth, height: collapsedHeight))"
      )

      window.setFrame(
        NSRect(x: xPosition, y: yPosition, width: collapsedWidth, height: collapsedHeight),
        display: true,
        animate: true
      )
    }
  }

  func positionWindowExpanded(_ window: NSWindow) {
    print("Positioning window expanded")
    isExpanded = true

    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame

      let expandedWidth: CGFloat = lastExpandedSize?.width ?? 450
      let expandedHeight: CGFloat = lastExpandedSize?.height ?? 650

      let xPosition = screenFrame.maxX - expandedWidth
      let yPosition = screenFrame.maxY - (screenFrame.height / 5) - expandedHeight

      window.setFrame(
        NSRect(x: xPosition, y: yPosition, width: expandedWidth, height: expandedHeight),
        display: true,
        animate: true
      )
    }
  }
}

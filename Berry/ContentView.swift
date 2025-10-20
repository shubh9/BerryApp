//
//  ContentView.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-08-08.
//

import AppKit
import SwiftUI

struct ContentView: View {
  @StateObject private var chrome = ChromeController()
  @StateObject private var notificationsVM = NotificationService()
  @StateObject private var rulesVM = RuleService()
  @State private var selectedTab: Tab = .rules
  @State private var isExpanded: Bool = false

  enum Tab: String, CaseIterable {
    case rules = "Rules"
    case notifications = "Notifications"
    case browser = "Browser"
  }

  // Check if there's a notification in the last 24 hours
  private var hasRecentNotification: Bool {
    let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
    return notificationsVM.notifications.contains { notification in
      guard let createdAt = notification.createdAt else { return false }
      return createdAt > twentyFourHoursAgo
    }
  }

  var body: some View {
    ZStack {
      if isExpanded {
        // Expanded view - Full UI
        expandedView
          .transition(.move(edge: .trailing).combined(with: .opacity))
      } else {
        // Collapsed view - Small tab with arrow
        collapsedView
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .task {
      await chrome.refreshRunningStatus()
      await notificationsVM.fetchOnce()
      notificationsVM.startPolling()
    }
    .onDisappear {
      notificationsVM.stopPolling()
    }
  }

  // MARK: - Collapsed View
  private var collapsedView: some View {
    Button(action: {
      expandWindow()
    }) {
      VStack(spacing: 8) {
        Image(systemName: "chevron.left")
          .font(.system(size: 16, weight: .semibold))

        Text("Berry")
          .font(.system(size: 10, weight: .medium))
          .rotationEffect(.degrees(-90))
      }
      .foregroundStyle(
        LinearGradient(
          gradient: Gradient(
            colors: hasRecentNotification
              ? [Color.white.opacity(0.6), Color.white.opacity(0.8)]
              : [Color.white.opacity(0.2), Color.white.opacity(0.4)]),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        LinearGradient(
          gradient: Gradient(
            colors: hasRecentNotification
              ? [Color.accentColor.opacity(0), Color.accentColor.opacity(1)]
              : [Color.gray.opacity(0), Color.gray.opacity(0.2)]),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .cornerRadius(8)
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
  }

  // MARK: - Expanded View
  private var expandedView: some View {
    VStack(spacing: 0) {
      // Header with close button
      HStack {
        Text("Berry")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        Button(action: {
          collapseWindow()
        }) {
          Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(width: 28, height: 28)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Color(NSColor.windowBackgroundColor))

      Divider()

      // Custom Tab Bar
      HStack(spacing: 0) {
        ForEach(Tab.allCases, id: \.self) { tab in
          Button(action: { selectedTab = tab }) {
            Text(tab.rawValue)
              .font(.headline)
              .foregroundColor(selectedTab == tab ? .primary : .secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
          }
          .buttonStyle(.plain)
        }
      }
      .background(Color.clear)

      Divider()

      // Tab Content
      Group {
        switch selectedTab {
        case .rules:
          RulesView(rulesVM: rulesVM)
        case .notifications:
          NotificationsView(notificationsVM: notificationsVM)
        case .browser:
          BrowserView(chrome: chrome)
        }
      }
    }
    .background(Color(NSColor.windowBackgroundColor))
    .cornerRadius(12)
    .shadow(color: Color.black.opacity(0.2), radius: 10, x: -2, y: 0)
  }

  // MARK: - Window Management
  private func expandWindow() {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      isExpanded = true
    }

    // Position window to expanded state
    DispatchQueue.main.asyncAfter(deadline: .now()) {
      if let window = NSApplication.shared.windows.first {
        if let appDelegate = AppDelegate.shared {
          appDelegate.positionWindowExpanded(window)
        }
      }
    }
  }

  private func collapseWindow() {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
      isExpanded = false
    }

    // Position window to collapsed state
    DispatchQueue.main.asyncAfter(deadline: .now()) {
      if let window = NSApplication.shared.windows.first,
        let appDelegate = AppDelegate.shared
      {
        appDelegate.positionWindowCollapsed(window)
      }
    }
  }
}

#Preview {
  ContentView()
}

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

  // Check if there are any unviewed notifications in the last 24 hours
  private var hasUnviewedNotification: Bool {
    return notificationsVM.hasUnviewedRecentNotifications()
  }

  // Count of unviewed notifications in the last 24 hours
  private var unviewedNotificationCount: Int {
    return notificationsVM.getRecentNotifications().filter {
      !notificationsVM.isNotificationViewed($0.id)
    }.count
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
            colors: hasUnviewedNotification
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
            colors: hasUnviewedNotification
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
            HStack(spacing: 6) {
              Text(tab.rawValue)
                .font(.headline)
                .foregroundColor(selectedTab == tab ? .primary : .secondary)

              // Notification badge for unviewed notifications
              if tab == .notifications && unviewedNotificationCount > 0 {
                ZStack {
                  Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)

                  Text("\(unviewedNotificationCount)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                }
              }
            }
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
      .onChange(of: selectedTab) { oldValue, newValue in
        // Mark all recent notifications as viewed when user LEAVES the notifications tab
        if oldValue == .notifications && newValue != .notifications {
          notificationsVM.markAllRecentAsViewed()
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
    // Mark notifications as viewed if user was on notifications tab
    if selectedTab == .notifications {
      notificationsVM.markAllRecentAsViewed()
    }

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

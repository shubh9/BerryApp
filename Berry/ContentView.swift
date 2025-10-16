//
//  ContentView.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-08-08.
//

import SwiftUI

struct ContentView: View {
  @StateObject private var chrome = ChromeController()
  @StateObject private var notificationsVM = NotificationService()
  @StateObject private var rulesVM = RuleService()
  @State private var selectedTab: Tab = .rules

  enum Tab: String, CaseIterable {
    case rules = "Rules"
    case notifications = "Notifications"
    case browser = "Browser"
  }

  var body: some View {
    VStack(spacing: 0) {
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
    .task {
      await chrome.refreshRunningStatus()
      await notificationsVM.fetchOnce()
      notificationsVM.startPolling()
    }
    .onDisappear {
      notificationsVM.stopPolling()
    }
  }
}

#Preview {
  ContentView()
}

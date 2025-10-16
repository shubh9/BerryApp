//
//  NotificationsView.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-10-13.
//

import SwiftUI

struct NotificationsView: View {
  @ObservedObject var notificationsVM: NotificationService

  // Filter to show only notifications from last 24 hours
  private var recentNotifications: [NotificationItem] {
    let cutoff = Date().addingTimeInterval(-24 * 60 * 60)  // 24 hours ago
    return notificationsVM.notifications.filter { notification in
      guard let createdAt = notification.createdAt else { return false }
      return createdAt >= cutoff
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header with refresh button
      HStack {
        Text("Notifications (Last 24h)")
          .font(.headline)

        Spacer()

        Button(action: {
          Task { await notificationsVM.fetchOnce() }
        }) {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
      }

      Divider()

      // Notifications list (last 24 hours)
      if recentNotifications.isEmpty {
        Text("No notifications from the last 24 hours")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(recentNotifications) { note in
              NotificationCard(note: note)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
    .padding(16)
  }
}

// MARK: - Notification Card Component
struct NotificationCard: View {
  let note: NotificationItem

  private var timestamp: String {
    if let d = note.createdAt {
      let f = DateFormatter()
      f.dateStyle = .short
      f.timeStyle = .short
      return f.string(from: d)
    }
    return "—"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Rule \(note.ruleId)")
          .font(.subheadline).fontWeight(.semibold)
        Spacer()
        Text(timestamp)
          .font(.caption).foregroundStyle(.secondary)
      }

      Text(note.result)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.gray.opacity(0.08))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.gray.opacity(0.2))
    )
  }
}

#Preview {
  NotificationsView(notificationsVM: NotificationService())
}

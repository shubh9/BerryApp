//
//  NotificationsView.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-10-13.
//

import MarkdownUI
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
              NotificationCard(
                note: note,
                isViewed: notificationsVM.isNotificationViewed(note.id)
              )
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
    .padding(16)
    .onAppear {
      Task { await notificationsVM.fetchOnce() }
    }
  }
}

// MARK: - Notification Card Component
struct NotificationCard: View {
  let note: NotificationItem
  let isViewed: Bool

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

        // NEW indicator for unviewed notifications
        if !isViewed {
          HStack(spacing: 4) {
            Image(systemName: "star.fill")
              .font(.caption2)
              .foregroundColor(.accentColor)
            Text("NEW")
              .font(.caption2)
              .fontWeight(.bold)
              .foregroundColor(.accentColor)
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(Color.accentColor.opacity(0.15))
          .cornerRadius(4)
        }

        Spacer()
        Text(timestamp)
          .font(.caption).foregroundStyle(.secondary)
      }

      Markdown(note.result)
        .markdownTextStyle(\.text) {
          FontSize(14)
        }
        .markdownTheme(.gitHub)
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
        .stroke(
          isViewed ? Color.gray.opacity(0.15) : Color.accentColor.opacity(0.3),
          lineWidth: isViewed ? 1 : 1.5
        )
    )
  }
}

#Preview {
  NotificationsView(notificationsVM: NotificationService())
}

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
  @State private var ruleText: String = ""
  @State private var sendingRule = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Browser controls
      HStack(spacing: 8) {
        Button(chrome.isRunning ? "Chrome Running" : "Start Browser") {
          Task { await chrome.start() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(chrome.isRunning)

        Button("Stop Browser") {
          chrome.stop()
        }
        .buttonStyle(.bordered)
        .disabled(!chrome.isRunning)

        Spacer(minLength: 0)

        Text(chrome.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Rule input
      HStack(spacing: 8) {
        TextField(
          "Enter a routine...", text: $ruleText,
          axis: .vertical
        )
        .textFieldStyle(.roundedBorder)
        .lineLimit(1...3)

        Button(sendingRule ? "Sending…" : "Send") {
          Task {
            let text = ruleText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            sendingRule = true
            do {
              try await RuleService.sendRule(userId: "Shubh", textPrompt: text)
              ruleText = ""
            } catch {
              print("Send rule failed: \(error)")
            }
            sendingRule = false
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(sendingRule || ruleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      Divider()

      // Notifications list
      if notificationsVM.notifications.isEmpty {
        Text("No notifications")
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(notificationsVM.notifications) { note in
              NotificationCard(note: note)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
    .padding(16)
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

private struct NotificationCard: View {
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
  ContentView()
}

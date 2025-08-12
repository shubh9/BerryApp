//
//  ContentView.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-08-08.
//

import SwiftUI

private struct NotificationItem: Identifiable, Decodable {
  let id: Int
  let ruleId: Int
  let userId: String
  let createdAt: Date?
  let result: String

  private enum CodingKeys: String, CodingKey {
    case id
    case createdAt = "created_at"
    case userId = "user_id"
    case ruleId = "rule_id"
    case payload
  }

  private struct Payload: Decodable { let result: String }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(Int.self, forKey: .id)
    self.ruleId = try container.decode(Int.self, forKey: .ruleId)
    self.userId = try container.decode(String.self, forKey: .userId)

    // Parse ISO8601 with fractional seconds when possible; fall back to nil
    if let createdString = try? container.decode(String.self, forKey: .createdAt) {
      let fmt = ISO8601DateFormatter()
      fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      self.createdAt = fmt.date(from: createdString)
    } else {
      self.createdAt = nil
    }

    let payload = try container.decode(Payload.self, forKey: .payload)
    self.result = payload.result
  }
}

struct ContentView: View {
  @StateObject private var chrome = ChromeController()
  @State private var notifications: [NotificationItem] = []
  @State private var pollTask: Task<Void, Never>? = nil

  var body: some View {
    NavigationSplitView {
      List {
        Section("Notifications") {
          if notifications.isEmpty {
            Text("No notifications")
              .foregroundStyle(.secondary)
          } else {
            ForEach(notifications) { note in
              VStack(alignment: .leading, spacing: 4) {
                Text("Rule: \(note.ruleId)")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                Text(note.result)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }
        }

        Section("Browser") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Status: \(chrome.statusText)")
              .font(.caption)
              .foregroundStyle(.secondary)
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
            }
            Button("Create Rule") {
              Task { await createRule() }
            }
            .buttonStyle(.bordered)
          }
          .padding(.vertical, 4)
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200)
      .task {
        await chrome.refreshRunningStatus()
        await fetchNotifications()
        startPolling()
      }
      .onDisappear { stopPolling() }
    } detail: {
      Text("Select a notification")
    }
  }

  // MARK: - Networking
  private func fetchNotifications() async {
    let url = AppConfig.serverURL.appendingPathComponent("notifications")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        if let http = response as? HTTPURLResponse {
          print("Fetch Notifications: server error \(http.statusCode)")
        }
        return
      }

      let decodedArray = try JSONDecoder().decode([NotificationItem].self, from: data)
      await MainActor.run {
        let existingIds = Set(self.notifications.map { $0.id })
        let newItems = decodedArray.filter { !existingIds.contains($0.id) }
        self.notifications.append(contentsOf: newItems)
      }
    } catch {
      print("Fetch Notifications: request failed: \(error)")
    }
  }

  private func createRule() async {
    do {
      var request = URLRequest(url: AppConfig.serverURL.appendingPathComponent("rule"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      let date = Date.now.formatted(date: .numeric, time: .standard)
      let body: [String: String] = [
        "userId": "Shubh",
        "textPrompt": "check the weather in san francisco on \(date)",
      ]
      request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

      let (_, response) = try await URLSession.shared.data(for: request)
      if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
        print("Create Rule: success \(http.statusCode)")
      } else if let http = response as? HTTPURLResponse {
        print("Create Rule: server error \(http.statusCode)")
      }
    } catch {
      print("Create Rule: request failed: \(error)")
    }
  }

  private func startPolling() {
    guard pollTask == nil else { return }
    print("Starting polling")

    pollTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        print("Polling for notifications")
        await fetchNotifications()
      }
    }
  }

  private func stopPolling() {
    pollTask?.cancel()
    pollTask = nil
  }
}

#Preview {
  ContentView()
}

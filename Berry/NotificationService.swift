import Foundation
import SwiftUI

struct NotificationItem: Identifiable, Decodable {
  let id: Int
  let ruleId: String
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
    self.ruleId = try container.decode(String.self, forKey: .ruleId)
    self.userId = try container.decode(String.self, forKey: .userId)

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

@MainActor
final class NotificationService: ObservableObject {
  @Published private(set) var notifications: [NotificationItem] = []
  @AppStorage("viewedNotificationIds") private var viewedIdsData: Data = Data()

  let authService: AuthService
  private var pollTask: Task<Void, Never>? = nil

  init(authService: AuthService) {
    self.authService = authService
  }

  private var viewedIds: Set<Int> {
    get {
      guard !viewedIdsData.isEmpty else { return Set() }
      return (try? JSONDecoder().decode(Set<Int>.self, from: viewedIdsData)) ?? Set()
    }
    set {
      viewedIdsData = (try? JSONEncoder().encode(newValue)) ?? Data()
    }
  }

  /// Check if a specific notification has been viewed
  func isNotificationViewed(_ id: Int) -> Bool {
    return viewedIds.contains(id)
  }

  /// Mark all recent notifications (last 24h) as viewed
  func markAllRecentAsViewed() {
    let recentNotifications = getRecentNotifications()
    let recentIds = recentNotifications.map { $0.id }
    viewedIds.formUnion(recentIds)
    objectWillChange.send()
  }

  /// Get notifications from the last 24 hours
  func getRecentNotifications() -> [NotificationItem] {
    let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
    return notifications.filter { notification in
      guard let createdAt = notification.createdAt else { return false }
      return createdAt >= cutoff
    }
  }

  /// Check if there are any unviewed notifications in the last 24 hours
  func hasUnviewedRecentNotifications() -> Bool {
    return getRecentNotifications().contains { !isNotificationViewed($0.id) }
  }

  // MARK: - Fetching & Polling

  func fetchOnce() async {
    guard let userId = authService.currentUserId else {
      print("❌ No authenticated user")
      return
    }

    print("🔄 Fetching notifications for user: \(userId)")
    let url = AppConfig.serverURL
      .appendingPathComponent("notifications")
      .appending(queryItems: [
        URLQueryItem(name: "userId", value: userId)
      ])

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        print(
          "❌ Fetch notifications failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        return
      }

      let decodedArray = try JSONDecoder().decode([NotificationItem].self, from: data)
      print("✅ Fetched \(decodedArray.count) notifications")
      self.notifications = decodedArray
    } catch {
      print("❌ Notifications fetch failed: \(error)")
    }
  }

  func startPolling(intervalSeconds: UInt64 = 60) {
    guard pollTask == nil else { return }
    pollTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
        await fetchOnce()
      }
    }
  }

  func stopPolling() {
    pollTask?.cancel()
    pollTask = nil
  }
}

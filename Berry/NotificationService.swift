import Foundation
import SwiftUI

struct NotificationItem: Identifiable, Decodable {
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
  private var pollTask: Task<Void, Never>? = nil

  func fetchOnce() async {
    let url = AppConfig.serverURL.appendingPathComponent("notifications")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        return
      }

      let decodedArray = try JSONDecoder().decode([NotificationItem].self, from: data)
      let existingIds = Set(self.notifications.map { $0.id })
      let newItems = decodedArray.filter { !existingIds.contains($0.id) }
      self.notifications.append(contentsOf: newItems)
    } catch {
      print("Notifications fetch failed: \(error)")
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

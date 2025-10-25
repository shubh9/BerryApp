import Foundation
import SwiftUI

struct RuleItem: Identifiable, Decodable {
  let id: String
  let userId: String
  let prompt: String
  let createdAt: Date?
  let cronId: String?
  let frequency: String?

  private enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case prompt
    case createdAt = "created_at"
    case cronId = "cron_id"
    case frequency
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.userId = try container.decode(String.self, forKey: .userId)
    self.prompt = try container.decode(String.self, forKey: .prompt)
    self.cronId = try? container.decode(String.self, forKey: .cronId)
    self.frequency = try? container.decode(String.self, forKey: .frequency)

    if let createdString = try? container.decode(String.self, forKey: .createdAt) {
      let fmt = ISO8601DateFormatter()
      fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      self.createdAt = fmt.date(from: createdString)
    } else {
      self.createdAt = nil
    }
  }

  static func sendRule(userId: String, textPrompt: String) async throws {
    print("📤 Sending rule: '\(textPrompt)'")
    let url = AppConfig.serverURL.appendingPathComponent("rule")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: String] = [
      "userId": userId,
      "textPrompt": textPrompt,
    ]
    request.httpBody = try JSONEncoder().encode(body)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      print("❌ Send rule failed: HTTP ")
      throw URLError(.badServerResponse)
    }
    print("✅ Rule sent successfully")
  }
}

@MainActor
final class RuleService: ObservableObject {
  @Published private(set) var rules: [RuleItem] = []

  func fetchRules() async {
    print("🔄 Fetching rules...")
    let url = AppConfig.serverURL
      .appendingPathComponent("rule")
      .appending(queryItems: [URLQueryItem(name: "userId", value: "Shubh")])

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        print("❌ Fetch rules failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        return
      }

      let decodedArray = try JSONDecoder().decode([RuleItem].self, from: data)
      print("✅ Fetched \(decodedArray.count) rules")
      self.rules = decodedArray
      print("📋 Rules updated in view model")
    } catch {
      print("❌ Rules fetch failed: \(error)")
    }
  }

  func deleteRule(ruleId: String) async throws {
    print("🗑️ Deleting rule: \(ruleId)")
    let url = AppConfig.serverURL
      .appendingPathComponent("rule")
      .appendingPathComponent(ruleId)

    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      print("❌ Delete rule failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
      throw URLError(.badServerResponse)
    }

    print("✅ Rule deleted successfully")

    // Refresh the rules list after successful deletion
    await fetchRules()
  }

  func executeRule(ruleId: String) async throws {
    print("▶️ Executing rule: \(ruleId)")
    let url = AppConfig.serverURL
      .appendingPathComponent("rule")
      .appendingPathComponent(ruleId)
      .appendingPathComponent("execute")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      print("❌ Execute rule failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
      throw URLError(.badServerResponse)
    }

    print("✅ Rule executed successfully")
  }
}

import Foundation

enum RuleService {
  static func sendRule(userId: String, textPrompt: String) async throws {
    var request = URLRequest(url: AppConfig.serverURL.appendingPathComponent("rule"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: String] = [
      "userId": userId,
      "textPrompt": textPrompt,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw NSError(
        domain: "RuleService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server error"])
    }
  }
}

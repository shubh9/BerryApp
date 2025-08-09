//
//  OperatorService.swift
//  Berry
//
//  Extracted OpenAI operator integration and orchestration logic.
//

import Foundation
import SwiftUI

// MARK: - Operator service: streams tool-calls and invokes CDP

@MainActor
final class OperatorService: ObservableObject {
  @Published var isRunning: Bool = false
  @Published var statusText: String = "Idle"

  var onStatusChange: ((String) -> Void)?

  private let cdp: CDPClient
  private var streamTask: Task<Void, Never>?

  init(debugPort: Int) {
    self.cdp = CDPClient(debugPort: debugPort)
  }

  func start(prompt: String) {
    guard !isRunning else { return }
    isRunning = true
    setStatus("Connecting to browser…")

    streamTask = Task { [weak self] in
      guard let self else { return }
      do {
        // Indefinite, cancellable connect loop with capped exponential backoff
        var backoffMs = 200
        var attempt = 0
        while true {
          try Task.checkCancellation()
          do {
            attempt += 1
            NSLog("[Operator] Connect attempt #\(attempt)")
            try await self.cdp.connect()
            break
          } catch {
            let secs = Double(backoffMs) / 1000.0
            await MainActor.run {
              self.setStatus(
                "Connecting to browser… (attempt #\(attempt); retrying in \(String(format: "%.1f", secs))s)"
              )
            }
            NSLog("[Operator] Connect failed on attempt #\(attempt): \(error)")
            try? await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
            backoffMs = min(backoffMs * 2, 5_000)  // cap at 5s
          }
        }

        await MainActor.run { self.setStatus("Connected. Starting operator…") }
        try await self.runOperatorNonStreaming(prompt: prompt)
        await MainActor.run { self.setStatus("Operator completed") }
      } catch is CancellationError {
        // Graceful cancellation; stop() already updates state/status
      } catch {
        await MainActor.run { self.setStatus("Error: \(error)") }
      }
      await MainActor.run { self.isRunning = false }
    }
  }

  func stop() {
    streamTask?.cancel()
    Task { await self.cdpClose() }
    isRunning = false
    setStatus("Stopped")
  }

  private func cdpClose() async { await cdp.close() }

  private func setStatus(_ text: String) {
    statusText = text
    onStatusChange?(text)
  }

  // MARK: OpenAI non-streaming loop
  private func runOperatorNonStreaming(prompt: String) async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
      throw NSError(
        domain: "OperatorService", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing OPENAI_API_KEY env var"])
    }

    var conversationItems: [[String: Any]] = [["role": "user", "content": prompt]]

    for turn in 1...24 {  // safety cap to avoid infinite loops
      try Task.checkCancellation()

      var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
      request.httpMethod = "POST"
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

      let body: [String: Any] = [
        "model": "computer-use-preview",
        "input": conversationItems,
        "tools": toolSchemas(),
        "truncation": "auto",
      ]
      request.httpBody = try JSONSerialization.data(withJSONObject: body)

      NSLog("[Operator] -> POST /v1/responses (turn=\(turn)) items=\(conversationItems.count)")
      let (data, _) = try await URLSession.shared.data(for: request)

      guard
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let output = obj["output"] as? [[String: Any]]
      else {
        await MainActor.run { self.setStatus("Bad response payload") }
        NSLog(
          "[Operator] <- invalid response payload: \(String(data: data, encoding: .utf8) ?? "<non-utf8>")"
        )
        break
      }

      let outputTypes = output.compactMap { $0["type"] as? String }
      NSLog("[Operator] <- output types: \(outputTypes)")

      var handledAnyTool = false

      for item in output {
        guard let type = item["type"] as? String else { continue }
        if type == "tool_call" || type == "function_call" || type == "computer_call" {
          handledAnyTool = true

          // Use the tool call's id as the call_id for outputs; fall back to call_id then UUID
          let callId = (item["id"] as? String) ?? (item["call_id"] as? String) ?? UUID().uuidString

          // Persist the original tool call in conversation so the API can match outputs to calls
          // Keep it intact (do not replace its id); just append as-is so the server recognizes it
          conversationItems.append(item)

          let name = (item["name"] as? String) ?? ""

          let argsAny = item["arguments"]
          let argsDict: [String: Any]
          if let s = argsAny as? String,
            let dict = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]
          {
            argsDict = dict
          } else {
            argsDict = (argsAny as? [String: Any]) ?? [:]
          }

          NSLog("[Operator] \(type) name=\(name) call_id=\(callId) args=\(argsDict)")

          let (toolOutputString, screenshotBase64) = await self.executeToolLocally(
            name: name, args: argsDict)

          // Append appropriate *_call_output based on call type
          let outputType =
            (type == "computer_call") ? "computer_call_output" : "function_call_output"
          conversationItems.append([
            "type": outputType,
            "call_id": callId,
            "output": toolOutputString,
          ])
          NSLog("[Operator] appended \(outputType) for call_id=\(callId)")

          // If screenshot present, add as input_image via data URL
          if let b64 = screenshotBase64 {
            conversationItems.append([
              "type": "input_image",
              "image_url": "data:image/png;base64,\(b64)",
            ])
            NSLog("[Operator] appended input_image (screenshot)")
          }
        }
      }

      if handledAnyTool { continue }

      if let finalText = extractAssistantText(from: output) {
        await MainActor.run { self.setStatus(finalText) }
        NSLog("[Operator] assistant final text: \(finalText.prefix(160))…")
        break
      }

      await MainActor.run { self.setStatus("No actionable output") }
      NSLog("[Operator] no tool calls and no assistant text; stopping")
      break
    }
  }

  private func toolSchemas() -> [[String: Any]] {
    return [
      [
        "type": "function",
        "name": "navigate",
        "description": "Navigate the browser to a URL",
        "parameters": [
          "type": "object",
          "properties": ["url": ["type": "string"]],
          "required": ["url"],
        ],
      ],
      [
        "type": "function",
        "name": "click",
        "description": "Click an element by CSS selector",
        "parameters": [
          "type": "object",
          "properties": ["selector": ["type": "string"]],
          "required": ["selector"],
        ],
      ],
      [
        "type": "function",
        "name": "type",
        "description": "Type text into an element by CSS selector",
        "parameters": [
          "type": "object",
          "properties": [
            "selector": ["type": "string"],
            "text": ["type": "string"],
          ],
          "required": ["selector", "text"],
        ],
      ],
      [
        "type": "function",
        "name": "evaluate",
        "description": "Run JavaScript in the page context",
        "parameters": [
          "type": "object",
          "properties": ["expression": ["type": "string"]],
          "required": ["expression"],
        ],
      ],
      [
        "type": "function",
        "name": "screenshot",
        "description": "Capture a screenshot of the current page",
        "parameters": ["type": "object", "properties": [:]],
      ],
    ]
  }

  // Execute a tool locally and return a JSON string output + optional screenshot base64
  private func executeToolLocally(name: String, args: [String: Any]) async -> (String, String?) {
    func stringify(_ obj: Any) -> String {
      if let data = try? JSONSerialization.data(withJSONObject: obj),
        let text = String(data: data, encoding: .utf8)
      {
        return text
      }
      return "{}"
    }

    do {
      switch name {
      case "navigate":
        if let url = args["url"] as? String {
          try await cdp.navigate(to: url)
          await MainActor.run { self.setStatus("Navigated to \(url)") }
          return (stringify(["ok": true, "action": name, "url": url]), nil)
        }
      case "click":
        if let sel = args["selector"] as? String {
          try await cdp.click(selector: sel)
          await MainActor.run { self.setStatus("Clicked \(sel)") }
          return (stringify(["ok": true, "action": name, "selector": sel]), nil)
        }
      case "type":
        if let sel = args["selector"] as? String, let text = args["text"] as? String {
          try await cdp.type(selector: sel, text: text)
          await MainActor.run { self.setStatus("Typed into \(sel)") }
          return (stringify(["ok": true, "action": name, "selector": sel]), nil)
        }
      case "evaluate":
        if let expr = args["expression"] as? String {
          let value = try await cdp.evaluate(expr)
          await MainActor.run { self.setStatus("Evaluated expression") }
          return (stringify(["ok": true, "action": name, "value": value ?? NSNull()]), nil)
        }
      case "screenshot":
        let data = try await cdp.screenshot()
        let b64 = data.base64EncodedString()
        await MainActor.run { self.setStatus("Captured screenshot") }
        return (stringify(["ok": true, "action": name]), b64)
      default:
        break
      }
    } catch {
      await MainActor.run { self.setStatus("Tool error: \(error)") }
      return (stringify(["ok": false, "error": "\(error)"]), nil)
    }

    return (stringify(["ok": false, "error": "invalid_arguments"]), nil)
  }

  private func extractAssistantText(from output: [[String: Any]]) -> String? {
    // Prefer message items with output_text content
    for item in output {
      if let type = item["type"] as? String, type == "message" {
        if let content = item["content"] as? [[String: Any]] {
          if let text = content.first(where: { ($0["type"] as? String) == "output_text" })?["text"]
            as? String
          {
            return text
          }
        }
        if let text = item["content"] as? String { return text }
      }
      if let type = item["type"] as? String, type == "output_text",
        let text = item["text"] as? String
      {
        return text
      }
    }
    return nil
  }
}

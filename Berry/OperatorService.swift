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
  private var currentDevicePixelRatio: Double = 1.0

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

      // Query the current viewport from the active page so the tool has accurate dimensions.
      guard let size = try? await self.cdp.viewportSize(), size.width > 0, size.height > 0 else {
        throw NSError(
          domain: "OperatorService", code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Failed to determine viewport size (width/height)"])
      }
      let cssWidth = size.width
      let cssHeight = size.height
      NSLog("[Operator] viewport size: \(cssWidth)x\(cssHeight)")
      let dpr = size.dpr
      currentDevicePixelRatio = max(0.5, dpr)
      // The screenshot is in device pixels. Provide display dimensions in device pixels
      // so the model's coordinates match the image pixels we send back.
      let displayWidth = Int(Double(cssWidth) * currentDevicePixelRatio)
      let displayHeight = Int(Double(cssHeight) * currentDevicePixelRatio)

      let body: [String: Any] = [
        "model": "computer-use-preview",
        "input": conversationItems,
        // Only expose the native computer tool; rely solely on computer_call
        "tools": [
          [
            "type": "computer-preview",
            "display_width": displayWidth,
            "display_height": displayHeight,
            "environment": "browser",
          ]
        ],
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

      // Add everything the model returned
      conversationItems.append(contentsOf: output)

      for item in output {
        guard let type = item["type"] as? String else { continue }
        if type == "computer_call" {
          handledAnyTool = true

          //   for (key, value) in item {
          //     NSLog("[Operator] item param: \(key) = \(value)")
          //   }

          // Use the tool call's id as the call_id for outputs
          guard let callId = item["call_id"] as? String else {
            NSLog("[Operator] missing tool-call id; skipping")
            continue
          }

          let pendingChecks = (item["pending_safety_checks"] as? [[String: Any]]) ?? []
          // Execute the computer action, then return an input_image
          do {
            let actionDict: [String: Any]
            if let a = item["action"] as? [String: Any] {
              actionDict = a
            } else if let aString = item["action"] as? String,
              let dict = try? JSONSerialization.jsonObject(with: Data(aString.utf8))
                as? [String: Any]
            {
              actionDict = dict
            } else {
              actionDict = [:]
            }

            let actionType = (actionDict["type"] as? String) ?? ""
            NSLog("[Operator] executing action type=\(actionType)")
            let t0 = Date()
            try await self.handleComputerAction(action: actionDict)
            let ms = Date().timeIntervalSince(t0) * 1000.0
            NSLog(
              "[Operator] action type=\(actionType) completed in \(String(format: "%.1f", ms))ms")

            let screenshotData = try await cdp.screenshot()
            let b64 = screenshotData.base64EncodedString()
            let currentUrl = try? await cdp.currentURL()

            conversationItems.append([
              "type": "computer_call_output",
              "call_id": callId,
              "acknowledged_safety_checks": pendingChecks,
              "output": [
                "type": "input_image",
                "image_url": "data:image/jpeg;base64,\(b64)",
                "current_url": (currentUrl as Any?) ?? NSNull(),
              ],
            ])
            NSLog("[Operator] executed computer action and appended image for call_id=\(callId)")
          } catch {
            conversationItems.append([
              "type": "computer_call_output",
              "call_id": callId,
              "acknowledged_safety_checks": pendingChecks,
              "output": [
                "type": "input_image",
                "image_url": NSNull(),
                "current_url": NSNull(),
                "error": "action_failed: \(error)",
              ],
            ])
            NSLog(
              "[Operator] action failed; appended error image payload for call_id=\(callId) error=\(error)"
            )
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

  // No-op; we now inline the computer tool in the request body
  private func toolSchemas() -> [[String: Any]] { return [] }

  // Execute a single computer action using our CDP client
  private func handleComputerAction(action: [String: Any]) async throws {
    let actionType = (action["type"] as? String) ?? ""
    var args = action
    args.removeValue(forKey: "type")

    await MainActor.run { self.setStatus("Executing: \(actionType)") }
    NSLog("[Operator] start action type=\(actionType) args=\(args)")

    // Helper to convert from model coords (device pixels) to CSS pixels for CDP
    func toCss(_ v: Int) -> Int {
      return Int((Double(v) / max(0.5, currentDevicePixelRatio)).rounded())
    }

    switch actionType {
    case "click":
      let x = toCss(args["x"] as? Int ?? 0)
      let y = toCss(args["y"] as? Int ?? 0)
      let button = (args["button"] as? String) ?? "left"
      try await cdp.clickAt(x: x, y: y, button: button)

    case "double_click":
      let x = toCss(args["x"] as? Int ?? 0)
      let y = toCss(args["y"] as? Int ?? 0)
      try await cdp.doubleClickAt(x: x, y: y)

    case "scroll":
      let x = toCss(args["x"] as? Int ?? 0)
      let y = toCss(args["y"] as? Int ?? 0)
      let scrollX = toCss(args["scroll_x"] as? Int ?? 0)
      let scrollY = toCss(args["scroll_y"] as? Int ?? 0)
      try await cdp.scrollBy(scrollX: scrollX, scrollY: scrollY, atX: x, atY: y)

    case "type":
      let text = args["text"] as? String ?? ""
      try await cdp.typeText(text)

    case "wait":
      let ms = args["ms"] as? Int ?? 1000
      NSLog("[Operator] wait for \(ms)ms")
      try await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)

    case "move":
      let x = toCss(args["x"] as? Int ?? 0)
      let y = toCss(args["y"] as? Int ?? 0)
      try await cdp.moveMouse(x: x, y: y)

    case "keypress":
      let keys = args["keys"] as? [String] ?? []
      try await cdp.keypress(keys: keys)

    case "drag":
      let rawPath = args["path"] as? [[String: Int]] ?? []
      let path: [[String: Int]] = rawPath.map { point in
        var out = point
        if let px = point["x"] { out["x"] = toCss(px) }
        if let py = point["y"] { out["y"] = toCss(py) }
        return out
      }
      try await cdp.drag(path: path)

    case "goto":
      if let url = args["url"] as? String { try await cdp.navigate(to: url) }

    case "back":
      try await cdp.back()

    case "forward":
      try await cdp.forward()

    case "screenshot":
      NSLog("[Operator] screenshot action; no-op")
      // No-op: we always capture a screenshot after executing the action
      return

    default:
      throw NSError(
        domain: "OperatorService", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported action: \(actionType)"])
    }
    NSLog("[Operator] end action type=\(actionType)")
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

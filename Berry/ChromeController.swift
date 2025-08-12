//
//  ChromeController.swift
//  Berry
//
//  Created by Assistant on 2025-08-08.
//

import Foundation
import SwiftUI

@MainActor
final class ChromeController: ObservableObject {
  enum ChromeError: Error { case failedToLaunch }

  // Use explicit user data directory as requested (sandbox is disabled)
  private let userDataDir: String =
    "/Users/shubhmittal/Desktop/Workshop/BerryUmbrella/chrome-operator"

  private let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  private let debuggingPort = 9222

  @Published var isRunning: Bool = false
  @Published var statusText: String = "Idle"
  private var launchedProcess: Process?
  private var stdoutPipe: Pipe?
  private var stderrPipe: Pipe?
  private let initialOperatorPrompt: String =
    "open gmail and open my first email in my promotions folders."
  //   private let initialOperatorPrompt: String =
  //     "open air canada's website and find the cheapest flight to toronto from sf"
  // Expose port for downstream clients
  var remoteDebuggingPort: Int { debuggingPort }

  // Operator service will be created after Chrome is up
  private var operatorService: OperatorService?

  private func chromeArgs() -> [String] {
    return [
      //   "--headless=new",  // use this for headless mode
      "--remote-debugging-port=\(debuggingPort)",
      "--user-data-dir=\(userDataDir)",
      "--profile-directory=Default",
      "--no-first-run",
      "--no-default-browser-check",
      "https://www.google.com/",
    ]
  }

  func start() async {
    if await !isDevToolsUp() {
      statusText = "Launching Chrome…"
      print("Launching Chrome")
      let ok = await launchChrome()
      if ok {
        isRunning = true
        statusText = "Chrome launched; starting operator…"
      } else {
        isRunning = false
        statusText = "Failed to launch Chrome"
        return
      }
    }
    startOperator(prompt: initialOperatorPrompt)
  }

  //   func start() async {
  //     // If a Chrome instance is already running on our devtools port, attach instead of launching
  //     if await isDevToolsUp() {

  //       isRunning = true
  //       statusText = "Chrome already running; starting operator…"
  //       startOperator(prompt: initialOperatorPrompt)
  //       return
  //     }
  //     print("Launching Chrome")

  //     statusText = "Launching Chrome…"
  //     let ok = await launchChrome()
  //     if ok {
  //       isRunning = true
  //       statusText = "Chrome launched; starting operator…"

  //       // Start the operator automatically with the requested prompt
  //       startOperator(prompt: initialOperatorPrompt)
  //     } else {
  //       isRunning = false
  //       statusText = "Failed to launch Chrome"
  //     }
  //   }

  private func startOperator(prompt: String) {
    let service = OperatorService(debugPort: debuggingPort)
    operatorService = service
    service.onStatusChange = { [weak self] text in
      Task { @MainActor in self?.statusText = text }
    }
    service.start(prompt: prompt)
  }

  // Update UI state based on whether something is already serving DevTools on our port.
  func refreshRunningStatus() async {
    let up = await isDevToolsUp()
    isRunning = up
    if up {
      if statusText == "Idle" || statusText.isEmpty {
        statusText = "Chrome detected"
      }
    } else {
      statusText = "Idle"
    }
  }

  func stop() {
    // Stop operator first
    operatorService?.stop()
    operatorService = nil

    // Terminate Chrome process if we launched it
    if let process = launchedProcess, process.isRunning {
      NSLog("[Chrome] Terminating pid=\(process.processIdentifier)")
      process.terminate()
      // Best-effort short wait for clean exit
      DispatchQueue.global().async {
        process.waitUntilExit()
      }
    }
    launchedProcess = nil
    stdoutPipe = nil
    stderrPipe = nil

    isRunning = false
    statusText = "Stopped"
  }

  private func launchChrome() async -> Bool {
    do {
      NSLog("[Chrome] Preparing user data dir at: \(userDataDir)")
      try FileManager.default.createDirectory(
        atPath: userDataDir,
        withIntermediateDirectories: true
      )
      NSLog("[Chrome] User data dir exists: \(FileManager.default.fileExists(atPath: userDataDir))")

      // Clean up any stale singleton artifacts from previous crashes
      if !(await isDevToolsUp()) {
        cleanupProfileArtifacts()
      } else {
        NSLog("[Chrome] DevTools endpoint already up; skipping artifact cleanup")
      }

      let chromeExists = FileManager.default.fileExists(atPath: chromePath)
      let chromeExecutable = FileManager.default.isExecutableFile(atPath: chromePath)
      NSLog("[Chrome] Binary: \(chromePath) exists=\(chromeExists) exec=\(chromeExecutable)")

      let args = chromeArgs()
      NSLog("[Chrome] Args: \(args.joined(separator: " "))")

      let process = Process()
      process.executableURL = URL(fileURLWithPath: chromePath)
      process.arguments = args

      let outPipe = Pipe()
      let errPipe = Pipe()
      stdoutPipe = outPipe
      stderrPipe = errPipe
      process.standardOutput = outPipe
      process.standardError = errPipe

      outPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { NSLog("[Chrome stdout] \(trimmed)") }
      }
      errPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { NSLog("[Chrome stderr] \(trimmed)") }
      }

      process.terminationHandler = { proc in
        NSLog("[Chrome] Terminated status=\(proc.terminationStatus)")
        Task { @MainActor in
          self.isRunning = false
          if self.statusText.lowercased().contains("starting operator") {
            self.statusText = "Chrome exited"
          }
        }
      }

      try process.run()
      launchedProcess = process
      NSLog("[Chrome] Launched pid=\(process.processIdentifier)")
      return true
    } catch {
      NSLog("Failed to launch Chrome: \(error)")
      return false
    }
  }

  // Checks whether something is already serving the DevTools protocol on our port.
  // If true, Chrome is already running (likely with our profile) and we should attach instead of launching.
  private func isDevToolsUp() async -> Bool {
    guard let url = URL(string: "http://127.0.0.1:\(debuggingPort)/json/version") else {
      return false
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 0.5
    do {
      _ = try await URLSession.shared.data(for: request)
      return true
    } catch {
      return false
    }
  }

  private func cleanupProfileArtifacts() {
    let names = [
      "SingletonLock",
      "SingletonCookie",
      "DevToolsActivePort",
    ]
    for name in names {
      let path = URL(fileURLWithPath: userDataDir).appendingPathComponent(name).path
      if FileManager.default.fileExists(atPath: path) {
        do {
          try FileManager.default.removeItem(atPath: path)
          NSLog("[Chrome] Removed stale artifact: \(name)")
        } catch {
          NSLog("[Chrome] Failed to remove artifact \(name): \(error)")
        }
      }
    }
  }
}

// MARK: - Minimal Chrome DevTools Protocol client

actor CDPClient {
  struct CDPError: Error { let message: String }

  private let debugPort: Int
  private var webSocketTask: URLSessionWebSocketTask?
  private var receiveLoopTask: Task<Void, Never>?
  private var nextMessageId: Int = 1
  private var pendingContinuations: [Int: CheckedContinuation<[String: Any], Error>] = [:]
  // Track method names and send timestamps for minimal response logging
  private var pendingMeta: [Int: (method: String, sentAt: Date)] = [:]

  init(debugPort: Int) { self.debugPort = debugPort }

  func connect() async throws {
    if webSocketTask != nil { return }

    // Prefer a page target WebSocket over the browser-level endpoint
    guard let wsURL = try await fetchPageWebSocketURL() else {
      throw CDPError(message: "No page target available")
    }

    NSLog("[CDP] Fetched page WS URL: \(wsURL.absoluteString)")
    let session = URLSession(configuration: .default)
    let task = session.webSocketTask(with: wsURL)
    task.resume()
    webSocketTask = task

    NSLog("[CDP] WebSocket task resumed; starting receive loop")
    receiveLoopTask = Task { await self.receiveLoop() }

    // Verify connectivity with a ping (best-effort)
    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      task.sendPing { _ in cont.resume() }
    }

    try await enableCoreDomains()
  }

  func close() async {
    receiveLoopTask?.cancel()
    webSocketTask?.cancel(with: .goingAway, reason: nil)
    webSocketTask = nil
  }

  // MARK: CDP plumbing
  private func receiveLoop() async {
    guard let ws = webSocketTask else { return }
    NSLog("[CDP] Entering receive loop")
    while true {
      do {
        let msg = try await ws.receive()
        switch msg {
        case .string(let text):
          try await handleInbound(text: text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) { try await handleInbound(text: text) }
        @unknown default:
          break
        }
      } catch {
        NSLog("[CDP] Receive loop error/exit: \(error)")
        break
      }
    }
  }

  private func handleInbound(text: String) async throws {
    guard let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
      return
    }
    if let id = obj["id"] as? Int, let cont = pendingContinuations.removeValue(forKey: id) {
      // Minimal response log with method name and latency
      let meta = pendingMeta.removeValue(forKey: id)
      let method = meta?.method ?? "?"
      let elapsedMs: String = {
        guard let t0 = meta?.sentAt else { return "-" }
        let ms = Date().timeIntervalSince(t0) * 1000.0
        return String(format: "%.1f", ms)
      }()
      if let err = obj["error"] {
        NSLog("[CDP] <- recv id=\(id) method=\(method) ERROR=\(err)")
      } else {
        NSLog("[CDP] <- recv id=\(id) method=\(method) in \(elapsedMs)ms")
      }
      cont.resume(returning: obj)
    }
  }

  @discardableResult
  private func send(method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
    guard let ws = webSocketTask else { throw CDPError(message: "Not connected") }
    let id = nextMessageId
    nextMessageId += 1
    let payload: [String: Any] = ["id": id, "method": method, "params": params]
    let data = try JSONSerialization.data(withJSONObject: payload)
    guard let text = String(data: data, encoding: .utf8) else {
      throw CDPError(message: "Failed to encode JSON as UTF-8 string")
    }
    NSLog("[CDP] -> send id=\(id) method=\(method) params=\(params)")
    return try await withCheckedThrowingContinuation {
      (cont: CheckedContinuation<[String: Any], Error>) in
      pendingContinuations[id] = cont
      pendingMeta[id] = (method: method, sentAt: Date())
      ws.send(.string(text)) { [weak self] err in
        guard let self, let err = err else { return }
        // Hop back to the actor to mutate state safely
        Task { await self.failPending(id: id, error: err) }
      }
    }
  }

  private func failPending(id: Int, error: Error) {
    if let cont = pendingContinuations.removeValue(forKey: id) {
      cont.resume(throwing: error)
    }
  }

  private func enableCoreDomains() async throws {
    _ = try await send(method: "Page.enable")
    _ = try await send(method: "Runtime.enable")
    _ = try await send(method: "DOM.enable")
  }

  // MARK: Target discovery
  private func fetchPageWebSocketURL() async throws -> URL? {
    // Single-attempt probe; outer connect loop owns retries
    struct Target: Decodable {
      let type: String
      let url: String
      let webSocketDebuggerUrl: String?
    }
    let listURL = URL(string: "http://127.0.0.1:\(debugPort)/json")!
    do {
      let (data, _) = try await URLSession.shared.data(from: listURL)
      let targets = try JSONDecoder().decode([Target].self, from: data)
      if let page = targets.first(where: { $0.type == "page" && $0.webSocketDebuggerUrl != nil }) {
        return URL(string: page.webSocketDebuggerUrl!)
      }
    } catch {
      // fallthrough to try create a new target once
    }

    // Try to create a new tab once
    let newURL = URL(string: "http://127.0.0.1:\(debugPort)/json/new?https://www.google.com/")!
    if let (newData, _) = try? await URLSession.shared.data(from: newURL) {
      struct NewTarget: Decodable { let webSocketDebuggerUrl: String }
      if let created = try? JSONDecoder().decode(NewTarget.self, from: newData) {
        return URL(string: created.webSocketDebuggerUrl)
      }
    }
    return nil
  }

  // MARK: Primitives
  func navigate(to url: String) async throws {
    _ = try await send(method: "Page.navigate", params: ["url": url])
  }

  @discardableResult
  func evaluate(_ expression: String) async throws -> Any? {
    let response = try await send(
      method: "Runtime.evaluate",
      params: [
        "expression": expression,
        "returnByValue": true,
      ])
    if let result = response["result"] as? [String: Any],
      let inner = result["result"] as? [String: Any]
    {
      return inner["value"]
    }
    return nil
  }

  func click(selector: String) async throws {
    let js = """
      (function(){
        const el = document.querySelector(\(jsonString(selector)));
        if(!el) return false;
        el.scrollIntoView({block:'center', inline:'center'});
        el.click();
        return true;
      })();
      """
    let ok = (try await evaluate(js) as? Bool) ?? false
    NSLog("[CDP] click(selector: \(selector)) result=\(ok)")
  }

  func type(selector: String, text: String) async throws {
    let js = """
      (function(){
        const el = document.querySelector(\(jsonString(selector)));
        if(!el) return false;
        el.focus();
        if('value' in el) {
          el.value = \(jsonString(text));
          el.dispatchEvent(new Event('input', {bubbles:true}));
          el.dispatchEvent(new Event('change', {bubbles:true}));
          return true;
        }
        return false;
      })();
      """
    let ok = (try await evaluate(js) as? Bool) ?? false
    NSLog("[CDP] type(selector: \(selector), textLen: \(text.count)) result=\(ok)")
  }

  func waitForSelector(_ selector: String, timeoutMs: Int = 10_000, intervalMs: Int = 200)
    async throws -> Bool
  {
    let start = Date()
    while Date().timeIntervalSince(start) * 1000 < Double(timeoutMs) {
      if let ok = try await evaluate("document.querySelector(\(jsonString(selector))) !== null")
        as? Bool, ok
      {
        return true
      }
      try await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
    }
    return false
  }

  func screenshot() async throws -> Data {
    // Use JPEG with moderate quality to keep message size under ~1MB limit of URLSessionWebSocketTask
    let res = try await send(
      method: "Page.captureScreenshot",
      params: [
        "format": "jpeg",
        "quality": 60,  // adjust if needed to stay under message limit
        "optimizeForSpeed": true,
      ])
    guard let result = res["result"] as? [String: Any],
      let b64 = result["data"] as? String,
      let data = Data(base64Encoded: b64)
    else {
      throw CDPError(message: "No screenshot data")
    }
    return data
  }

  // Best-effort viewport metrics (CSS pixels and device pixel ratio)
  func viewportSize() async throws -> (width: Int, height: Int, dpr: Double) {
    let wAny = try await evaluate("window.innerWidth")
    let hAny = try await evaluate("window.innerHeight")
    let dprAny = try await evaluate("window.devicePixelRatio")

    let width: Int = {
      if let i = wAny as? Int { return i }
      if let d = wAny as? Double { return Int(d.rounded()) }
      return 0
    }()
    let height: Int = {
      if let i = hAny as? Int { return i }
      if let d = hAny as? Double { return Int(d.rounded()) }
      return 0
    }()
    let dpr: Double = {
      if let d = dprAny as? Double { return d }
      if let i = dprAny as? Int { return Double(i) }
      return 1.0
    }()
    return (max(0, width), max(0, height), max(0.5, dpr))
  }

  // Best-effort read of the current URL from the page via document.location.href
  func currentURL() async throws -> String? {
    let expr = "document.location.href"
    if let value = try await evaluate(expr) as? String {
      return value
    }
    return nil
  }

  // MARK: Input: mouse
  func moveMouse(x: Int, y: Int) async throws {
    _ = try await send(
      method: "Input.dispatchMouseEvent",
      params: [
        "type": "mouseMoved",
        "x": x,
        "y": y,
        "buttons": 0,
      ])
  }

  func clickAt(x: Int, y: Int, button: String = "left") async throws {
    let btn = canonicalMouseButton(button)
    // Move first
    try await moveMouse(x: x, y: y)
    // Press
    _ = try await send(
      method: "Input.dispatchMouseEvent",
      params: [
        "type": "mousePressed",
        "x": x,
        "y": y,
        "button": btn,
        "clickCount": 1,
      ])
    // Release
    _ = try await send(
      method: "Input.dispatchMouseEvent",
      params: [
        "type": "mouseReleased",
        "x": x,
        "y": y,
        "button": btn,
        "clickCount": 1,
      ])
  }

  func doubleClickAt(x: Int, y: Int) async throws {
    try await clickAt(x: x, y: y, button: "left")
    // Short delay between clicks
    try? await Task.sleep(nanoseconds: 80_000_000)
    try await clickAt(x: x, y: y, button: "left")
  }

  func drag(path: [[String: Int]]) async throws {
    guard let first = path.first, let last = path.last else { return }
    let startX = first["x"] ?? 0
    let startY = first["y"] ?? 0
    // Move and press
    try await moveMouse(x: startX, y: startY)
    _ = try await send(
      method: "Input.dispatchMouseEvent",
      params: [
        "type": "mousePressed",
        "x": startX,
        "y": startY,
        "button": "left",
        "clickCount": 1,
      ])
    // Move along path (skip first)
    for point in path.dropFirst() {
      let x = point["x"] ?? last["x"] ?? startX
      let y = point["y"] ?? last["y"] ?? startY
      _ = try await send(
        method: "Input.dispatchMouseEvent",
        params: [
          "type": "mouseMoved",
          "x": x,
          "y": y,
          "buttons": 1,
        ])
    }
    // Release at last
    let endX = last["x"] ?? startX
    let endY = last["y"] ?? startY
    _ = try await send(
      method: "Input.dispatchMouseEvent",
      params: [
        "type": "mouseReleased",
        "x": endX,
        "y": endY,
        "button": "left",
        "clickCount": 1,
      ])
  }

  func scrollBy(scrollX: Int, scrollY: Int, atX x: Int, atY y: Int) async throws {
    _ = try await send(
      method: "Input.dispatchMouseEvent",
      params: [
        "type": "mouseWheel",
        "x": x,
        "y": y,
        "deltaX": scrollX,
        "deltaY": scrollY,
      ])
  }

  private func canonicalMouseButton(_ name: String) -> String {
    let lower = name.lowercased()
    switch lower {
    case "left", "primary": return "left"
    case "right", "secondary": return "right"
    case "middle": return "middle"
    default: return "left"
    }
  }

  // MARK: Input: keyboard
  func typeText(_ text: String) async throws {
    // InsertText types the given text into the focused element
    _ = try await send(method: "Input.insertText", params: ["text": text])
  }

  func keypress(keys: [String]) async throws {
    guard !keys.isEmpty else { return }
    let mainKey = keys.last!
    let modifiers = modifierMask(from: keys.dropLast())

    // Try to ensure the browser window has focus for system shortcuts
    if modifiers != 0 {
      try? await bringBrowserToFront()
    }

    // For modifier combinations, don't include text to avoid conflicts
    let includeText = modifiers == 0

    let paramsDown: [String: Any] = [
      "type": "rawKeyDown",
      "key": mainKey,
      "windowsVirtualKeyCode": windowsVK(mainKey),
      "modifiers": modifiers,
      "text": includeText ? textForKey(mainKey) : "",
    ]
    _ = try await send(method: "Input.dispatchKeyEvent", params: paramsDown)

    // Add small delay between keyDown and keyUp for better compatibility
    try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

    let paramsUp: [String: Any] = [
      "type": "keyUp",
      "key": mainKey,
      "windowsVirtualKeyCode": windowsVK(mainKey),
      "modifiers": modifiers,
    ]
    _ = try await send(method: "Input.dispatchKeyEvent", params: paramsUp)
  }

  private func bringBrowserToFront() async throws {
    // Try to bring the browser window to front using JavaScript focus
    _ = try? await evaluate("window.focus(); undefined")

    // Small delay to allow focus to take effect
    try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
  }

  private func modifierMask<S: Sequence>(from mods: S) -> Int where S.Element == String {
    var mask = 0
    for m in mods.map({ $0.lowercased() }) {
      switch m {
      case "alt", "option": mask |= 1
      case "control", "ctrl": mask |= 2
      case "shift": mask |= 4
      case "meta", "command", "cmd", "super": mask |= 8
      default: break
      }
    }
    return mask
  }

  private func windowsVK(_ key: String) -> Int {
    // Minimal mapping; letters/numbers fallback using ASCII
    let lower = key.lowercased()
    switch lower {
    case "enter", "return": return 13
    case "tab": return 9
    case "escape", "esc": return 27
    case "backspace": return 8
    case "delete": return 46
    case "arrowleft", "left": return 37
    case "arrowup", "up": return 38
    case "arrowright", "right": return 39
    case "arrowdown", "down": return 40
    default:
      if let scalar = key.unicodeScalars.first {
        return Int(scalar.value)
      }
      return 0
    }
  }

  private func textForKey(_ key: String) -> String {
    // Provide printable character if appropriate
    if key.count == 1 { return key }
    switch key.lowercased() {
    case "enter", "return": return "\n"
    case "tab": return "\t"
    default: return ""
    }
  }

  // MARK: History
  func back() async throws {
    _ = try await evaluate("history.back(); undefined")
  }

  func forward() async throws {
    _ = try await evaluate("history.forward(); undefined")
  }

  // MARK: Tab management
  func openNewTab(url: String = "about:blank") async throws {
    // Use JavaScript to open a new tab - more reliable than Ctrl+T
    _ = try await evaluate("window.open('\(url)', '_blank'); undefined")
  }

  private func jsonString(_ s: String) -> String {
    // Encode as JSON array then strip brackets to get a quoted string
    let data = try! JSONSerialization.data(withJSONObject: [s])
    let raw = String(data: data, encoding: .utf8)!
    return String(raw.dropFirst().dropLast())
  }
}

// OperatorService moved to `OperatorService.swift`.

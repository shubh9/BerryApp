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

  private func chromeArgs() -> [String] {
    return [
      "--headless=new",
      "--remote-debugging-port=\(debuggingPort)",
      "--user-data-dir=\(userDataDir)",
      "--profile-directory=Default",
      "--no-first-run",
      "--no-default-browser-check",
      "about:blank",
    ]
  }

  func start() async {
    statusText = "Launching Chrome…"
    let ok = await launchChrome()
    if ok {
      isRunning = true
      statusText = "Chrome launched with user dir"
    } else {
      isRunning = false
      statusText = "Failed to launch Chrome"
    }
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
      cleanupProfileArtifacts()

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

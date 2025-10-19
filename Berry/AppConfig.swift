//
//  AppConfig.swift
//  Berry
//
//  Centralized application configuration values.
//

import Foundation

enum AppConfig {
  // Base server URL used by network requests throughout the app.
  // Update this value to point to the desired backend environment.
  static let serverURL: URL = URL(string: "http://localhost:3000")!
}

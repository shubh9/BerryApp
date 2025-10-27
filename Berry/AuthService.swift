//
//  AuthService.swift
//  Berry
//
//  Authentication service for managing user login and session persistence.
//

import Foundation
import SwiftUI

// User model matching Supabase berry_users table
struct User: Codable {
  let id: String
  let name: String
  let loginCode: String
  let createdAt: String?  // Temporarily changed to String for debugging

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case loginCode = "login_code"
    case createdAt = "created_at"
  }
}

@MainActor
final class AuthService: ObservableObject {
  @Published private(set) var isAuthenticated: Bool = false
  @Published private(set) var currentUser: User? = nil
  @Published private(set) var isLoading: Bool = false
  @Published var errorMessage: String? = nil

  @AppStorage("userData") private var userDataString: String = ""

  // Computed property for easy access to userId
  var currentUserId: String? {
    return currentUser?.id
  }

  init() {
    loadStoredUser()
  }

  private func loadStoredUser() {
    guard !userDataString.isEmpty,
      let data = userDataString.data(using: .utf8),
      let user = try? JSONDecoder().decode(User.self, from: data)
    else {
      return
    }

    self.currentUser = user
    self.isAuthenticated = true
  }

  private func saveUser(_ user: User) {
    guard let data = try? JSONEncoder().encode(user),
      let jsonString = String(data: data, encoding: .utf8)
    else {
      return
    }

    userDataString = jsonString
  }

  func login(withCode loginCode: String) async throws {
    isLoading = true
    errorMessage = nil

    defer { isLoading = false }

    let url = AppConfig.serverURL
      .appendingPathComponent("auth")
      .appendingPathComponent("verify")

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = ["loginCode": loginCode]
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    if http.statusCode == 200 {
      let result = try JSONDecoder().decode(LoginResponse.self, from: data)
      self.currentUser = result.user
      self.isAuthenticated = true
      saveUser(result.user)
    } else if http.statusCode == 401 || http.statusCode == 404 {
      let error = AuthError.invalidCode
      errorMessage = error.errorDescription
      throw error
    } else {
      let error = AuthError.networkError
      errorMessage = error.errorDescription
      throw error
    }
  }

  func logout() {
    userDataString = ""
    currentUser = nil
    isAuthenticated = false
    errorMessage = nil
    UserDefaults.standard.removeObject(forKey: "viewedNotificationIds")
  }
}

struct LoginResponse: Codable {
  let user: User
}

enum AuthError: Error, LocalizedError {
  case invalidCode
  case networkError

  var errorDescription: String? {
    switch self {
    case .invalidCode:
      return "Invalid login code. Please try again."
    case .networkError:
      return "Network error. Please check your connection."
    }
  }
}

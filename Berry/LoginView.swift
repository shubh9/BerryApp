//
//  LoginView.swift
//  Berry
//
//  Login screen for entering authentication code.
//

import SwiftUI

struct LoginView: View {
  @StateObject private var authService: AuthService
  @State private var loginCode: String = ""

  init(authService: AuthService) {
    _authService = StateObject(wrappedValue: authService)
  }

  var body: some View {
    VStack(spacing: 24) {
      // Logo/Header
      VStack(spacing: 8) {
        Text("🍓")
          .font(.system(size: 60))

        Text("Berry")
          .font(.largeTitle)
          .fontWeight(.bold)

        Text("Enter your login code to continue")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .padding(.bottom, 20)

      // Login Code Input
      TextField("Login Code", text: $loginCode)
        .textFieldStyle(.roundedBorder)
        .font(.body)
        .disableAutocorrection(true)
        .disabled(authService.isLoading)
        .onSubmit {
          Task { await handleLogin() }
        }

      // Login Button
      Button(action: {
        Task { await handleLogin() }
      }) {
        if authService.isLoading {
          ProgressView()
            .progressViewStyle(.circular)
            .frame(width: 80, height: 25)
        } else {
          Text("Login")
            .frame(width: 80, height: 25)
            .fontWeight(.semibold)
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(loginCode.isEmpty || authService.isLoading)

      // Error Message
      if let errorMessage = authService.errorMessage {
        Text(errorMessage)
          .font(.body)
          .foregroundColor(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(40)
  }

  private func handleLogin() async {
    do {
      try await authService.login(withCode: loginCode)
    } catch {
      print("Login failed: \(error)")
    }
  }
}

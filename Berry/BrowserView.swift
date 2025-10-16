//
//  BrowserView.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-10-13.
//

import SwiftUI

struct BrowserView: View {
  @ObservedObject var chrome: ChromeController

  var body: some View {
    VStack(spacing: 16) {
      // Browser status indicator
      VStack(spacing: 8) {
        Image(systemName: chrome.isRunning ? "circle.fill" : "circle")
          .font(.system(size: 40))
          .foregroundColor(chrome.isRunning ? .green : .gray)

        Text(chrome.isRunning ? "Browser Running" : "Browser Stopped")
          .font(.headline)

        Text(chrome.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 32)

      Spacer()

      // Browser controls
      HStack(spacing: 12) {
        Button("Start Browser") {
          Task { await chrome.start() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(chrome.isRunning)
        .frame(maxWidth: .infinity)

        Button("Stop Browser") {
          chrome.stop()
        }
        .buttonStyle(.bordered)
        .disabled(!chrome.isRunning)
        .frame(maxWidth: .infinity)
      }
      .padding(.bottom, 16)
    }
    .padding(16)
  }
}

#Preview {
  BrowserView(chrome: ChromeController())
}

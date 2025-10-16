//
//  RulesView.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-10-13.
//

import SwiftUI

struct RulesView: View {
  @ObservedObject var rulesVM: RuleService
  @State private var ruleText: String = ""
  @State private var sendingRule = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Rule input
      HStack(spacing: 8) {
        TextField(
          "Enter a routine...", text: $ruleText,
          axis: .vertical
        )
        .textFieldStyle(.roundedBorder)
        .lineLimit(1...3)

        Button(sendingRule ? "Sending…" : "Send") {
          Task {
            let text = ruleText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            sendingRule = true
            do {
              try await RuleItem.sendRule(userId: "Shubh", textPrompt: text)
              ruleText = ""
              await rulesVM.fetchRules()  // Refresh rules after adding
            } catch {
              print("Send rule failed: \(error)")
            }
            sendingRule = false
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(sendingRule || ruleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      Divider()

      // Header with refresh button
      HStack {
        Text("Your Rules")
          .font(.headline)

        Spacer()

        Button(action: {
          Task { await rulesVM.fetchRules() }
        }) {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
      }

      Divider()

      // Rules list
      if rulesVM.rules.isEmpty {
        Text("No rules yet")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(rulesVM.rules) { rule in
              RuleCard(rule: rule)
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
    .padding(16)
    .task {
      await rulesVM.fetchRules()
    }
  }
}

// MARK: - Rule Card Component
struct RuleCard: View {
  let rule: RuleItem

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(rule.prompt)
        .font(.body)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)

      // Display frequency if available
      if let frequency = rule.frequency {
        HStack {
          Image(systemName: "clock.fill")
            .font(.caption2)
          Text(frequency)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.blue.opacity(0.08))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.blue.opacity(0.2))
    )
  }
}

#Preview {
  RulesView(rulesVM: RuleService())
}

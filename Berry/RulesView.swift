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

        Button(sendingRule ? "Creating Rule…" : "Send") {
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
              RuleCard(
                rule: rule,
                onExecute: {
                  do {
                    try await rulesVM.executeRule(ruleId: rule.id)
                  } catch {
                    print("Failed to execute rule: \(error)")
                  }
                },
                onDelete: {
                  do {
                    try await rulesVM.deleteRule(ruleId: rule.id)
                  } catch {
                    print("Failed to delete rule: \(error)")
                  }
                })
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
  let onExecute: () async -> Void
  let onDelete: () async -> Void
  @State private var isDeleting = false
  @State private var isExecuting = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
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

        // Execute button - Now with purple gradient and bigger size
        Button(action: {
          Task {
            isExecuting = true
            await onExecute()
            isExecuting = false
          }
        }) {
          Image(systemName: isExecuting ? "hourglass" : "play.circle")
            .font(.title2)  // Bigger size
            .foregroundStyle(
              LinearGradient(
                colors: [Color.purple, Color.pink.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .help("Execute rule now")

        // Delete button - Now bigger
        Button(action: {
          Task {
            isDeleting = true
            await onDelete()
            isDeleting = false
          }
        }) {
          Image(systemName: isDeleting ? "hourglass" : "trash")
            .foregroundColor(.gray)
            .font(.title3)  // Bigger size
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
        .help("Delete rule")
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

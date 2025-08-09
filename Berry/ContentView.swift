//
//  ContentView.swift
//  Berry
//
//  Created by Shubh Mittal on 2025-08-08.
//

import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var items: [Item]
  @StateObject private var chrome = ChromeController()

  var body: some View {
    NavigationSplitView {
      List {
        ForEach(items) { item in
          NavigationLink {
            Text(
              "Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))"
            )
          } label: {
            Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
          }
        }
        .onDelete(perform: deleteItems)
        Section("Browser") {
          VStack(alignment: .leading, spacing: 8) {
            Text("Status: \(chrome.statusText)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Button(chrome.isRunning ? "Chrome Running" : "Start Browser") {
              Task { await chrome.start() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(chrome.isRunning)
          }
          .padding(.vertical, 4)
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200)
      .toolbar {
        ToolbarItem {
          Button(action: addItem) {
            Label("Add Item", systemImage: "plus")
          }
        }
      }
    } detail: {
      Text("Select an item")
    }
  }

  private func addItem() {
    withAnimation {
      let newItem = Item(timestamp: Date())
      modelContext.insert(newItem)
    }
  }

  private func deleteItems(offsets: IndexSet) {
    withAnimation {
      for index in offsets {
        modelContext.delete(items[index])
      }
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: Item.self, inMemory: true)
}

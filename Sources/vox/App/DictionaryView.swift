import AppKit
import SwiftUI

/// Standalone Dictionary editor used within the Personalization destination.
/// Backed by `DictionaryStore.shared`.
public struct DictionaryView: View {
    @StateObject private var dict = DictionaryStore.shared
    @State private var editingEntry: DictionaryEntry?
    @State private var isAddingEntry: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dictionary")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    editingEntry = DictionaryEntry(
                        id: "user-\(UUID().uuidString)",
                        spoken: "", replacement: "",
                        mode: .command, isBuiltIn: false
                    )
                    isAddingEntry = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([dict.fileURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }

            if let err = dict.loadError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            let userEntries = dict.entries.filter { !$0.isBuiltIn }
            let builtinCount = dict.entries.count - userEntries.count
            let disabledCount = userEntries.filter { !$0.enabled }.count

            ScrollView {
                LazyVStack(spacing: 0) {
                    if userEntries.isEmpty {
                        VStack(spacing: 6) {
                            Text("No custom entries yet.")
                                .foregroundStyle(.secondary)
                            Text("Click Add to create one.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(builtinCount) built-in fixups active")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(userEntries.enumerated()), id: \.element.id) { idx, entry in
                            DictionaryRow(
                                entry: entry,
                                onToggle: { dict.setEnabled(id: entry.id, enabled: !entry.enabled) },
                                onEdit: { editingEntry = entry; isAddingEntry = false },
                                onDelete: { dict.delete(id: entry.id) }
                            )
                            .padding(.horizontal, 8)
                            if idx < userEntries.count - 1 { Divider() }
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            Text("\(userEntries.count) custom entries · \(disabledCount) disabled · \(builtinCount) built-in fixups active")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editingEntry) { entry in
            DictionaryEditSheet(
                entry: entry,
                isNew: isAddingEntry,
                onSave: { saved in
                    if isAddingEntry { dict.add(saved) } else { dict.update(saved) }
                    editingEntry = nil
                },
                onCancel: { editingEntry = nil }
            )
        }
    }
}

// TFTP Server — a native macOS GUI for the built-in TFTP service.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

/// "TFTP Server Help" window (`CommandGroup(replacing: .help)` in
/// `TFTPServerApp`) — jensyleo's own request (2026-09-05): "el help de la
/// app debe ser como el de ROMForge". Same `NavigationSplitView` +
/// `.searchable` sidebar, same term-row styling for enumerable
/// actions/settings as ROMForge/HardwareSentry's own `HelpView`/`HelpTopic`.
/// Content in `HelpTopic.swift` — update it whenever a feature is added.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var topics: [HelpTopic] = HelpLibrary.topics
    @State private var selection: HelpTopic.ID? = HelpLibrary.topics.first?.id
    @State private var query = ""

    private var matches: [HelpTopic] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return topics }
        return topics.filter { topic in
            if topic.title.lowercased().contains(needle) { return true }
            return topic.sections.contains { section in
                (section.heading?.lowercased().contains(needle) ?? false)
                    || section.paragraphs.contains { $0.lowercased().contains(needle) }
                    || section.rows.contains {
                        $0.term.lowercased().contains(needle) || $0.detail.lowercased().contains(needle)
                    }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(matches) { topic in
                        Label(topic.title, systemImage: topic.symbol).tag(topic.id)
                    }
                }
                .searchable(text: $query, placement: .sidebar, prompt: "Search help")
                .navigationSplitViewColumnWidth(min: 220, ideal: 240)
                .overlay {
                    if matches.isEmpty {
                        emptySearchState
                    }
                }
            } detail: {
                if let topic = topics.first(where: { $0.id == selection }) {
                    TopicPage(topic: topic)
                } else {
                    pickTopicState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var emptySearchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No results for \"\(query)\"")
                .font(.headline)
        }
    }

    private var pickTopicState: some View {
        VStack(spacing: 8) {
            Image(systemName: "book")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Pick a topic")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TopicPage: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(topic.title)
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)

                ForEach(topic.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if let heading = section.heading {
                            Text(heading).font(.title3.weight(.semibold))
                        }

                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !section.rows.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                    if index > 0 { Divider() }
                                    TermRow(row: row)
                                }
                            }
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            // Kept near 65 characters of running text; a help page read
            // edge to edge on a wide window is a help page nobody finishes.
            .frame(maxWidth: 620, alignment: .leading)
            .textSelection(.enabled)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TermRow: View {
    let row: HelpSection.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.term).font(.body.weight(.medium))
                if let note = row.note {
                    Text(note)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(row.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

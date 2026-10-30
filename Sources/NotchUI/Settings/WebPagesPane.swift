import AppKit
import NotchCore
import SwiftUI

struct WebPagesPane: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var favicons: FaviconCache
    @EnvironmentObject private var router: SettingsRouter
    @State private var editing: WebShortcut?
    @State private var isAdding = false

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .webPages, subtitle: "Saved sites show up as icons in the island. Click one to open it in your browser.")
            }

            Section {
                if model.settings.shortcuts.isEmpty {
                    Text("No web pages yet. Add one below or pick a suggestion.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.settings.shortcuts) { shortcut in
                    ShortcutRow(
                        shortcut: shortcut,
                        icon: favicons.icon(for: shortcut),
                        edit: { editing = shortcut },
                        remove: { withAnimation { model.removeShortcut(id: shortcut.id) } }
                    )
                }
                .onMove { source, destination in
                    model.moveShortcuts(from: source, to: destination)
                }
                Button {
                    isAdding = true
                } label: {
                    Label("Add Web Page…", systemImage: "plus")
                }
            } header: {
                Text("Your Web Pages")
            } footer: {
                Text("Drag rows to reorder. In the island you can also drag a link from your browser onto the notch to save it, or click the grid button to rearrange and remove icons.")
            }

            Section("Suggestions") {
                let available = WebShortcutPreset.all.filter { preset in
                    guard let candidate = preset.shortcut else { return false }
                    return !model.settings.containsShortcut(for: candidate.url)
                }
                if available.isEmpty {
                    Text("You've added every suggestion.").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(available) { preset in
                            Button {
                                guard let shortcut = preset.shortcut else { return }
                                withAnimation { model.addShortcut(shortcut) }
                                favicons.load(shortcut)
                            } label: {
                                Label(preset.name, systemImage: "plus.circle.fill")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .glassButtonStyle()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isAdding) {
            ShortcutEditor(existing: nil) { shortcut in
                model.addShortcut(shortcut)
                favicons.load(shortcut)
            }
        }
        .sheet(item: $editing) { shortcut in
            ShortcutEditor(existing: shortcut) { updated in
                model.updateShortcut(updated)
                favicons.load(updated)
            }
        }
        .onAppear {
            favicons.load(model.settings.shortcuts)
            consumeAddRequest()
        }
        .onChange(of: router.wantsAddWebPage) { _, _ in consumeAddRequest() }
    }

    /// The island's + button opens Settings straight to the Add Web Page sheet.
    private func consumeAddRequest() {
        guard router.wantsAddWebPage else { return }
        router.wantsAddWebPage = false
        isAdding = true
    }
}

private struct ShortcutRow: View {
    let shortcut: WebShortcut
    let icon: SiteIcon?
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SiteIconView(shortcut: shortcut, icon: icon, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(shortcut.name)
                Text(shortcut.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Edit", action: edit)
                .buttonStyle(.borderless)
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Remove \(shortcut.name)")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Open in Browser") { NSWorkspace.shared.open(shortcut.url) }
            Divider()
            Button("Remove", role: .destructive, action: remove)
        }
    }
}

struct ShortcutEditor: View {
    let existing: WebShortcut?
    let onSave: (WebShortcut) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String

    init(existing: WebShortcut?, onSave: @escaping (WebShortcut) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _address = State(initialValue: existing?.url.absoluteString ?? "")
    }

    private var normalizedURL: URL? { URLNormalizer.normalize(address) }

    private var suggestedName: String {
        normalizedURL.map { URLNormalizer.suggestedName(for: $0) } ?? "Discord"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                SettingsIcon(symbol: "globe", color: SettingsPane.webPages.color, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(existing == nil ? "Add Web Page" : "Edit Web Page")
                        .font(.system(size: 15, weight: .bold))
                    Text("Paste a link or type a site like discord.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                labeledField("Web address") {
                    TextField("discord.com/app", text: $address)
                        .textFieldStyle(.roundedBorder)
                }
                labeledField("Name") {
                    TextField(suggestedName, text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                if !address.trimmingCharacters(in: .whitespaces).isEmpty && normalizedURL == nil {
                    Label("That doesn't look like a web address.", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalizedURL == nil)
            }
        }
        .padding(22)
        .frame(width: 420)
        .preferredColorScheme(.dark)
    }

    private func labeledField<Field: View>(_ title: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            field()
        }
    }

    private func save() {
        guard let url = normalizedURL else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? URLNormalizer.suggestedName(for: url) : trimmed
        var shortcut = existing ?? WebShortcut(name: finalName, url: url)
        shortcut.name = finalName
        shortcut.url = url
        onSave(shortcut)
        dismiss()
    }
}

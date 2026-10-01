import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct SavedPresetsPanel: View {
    @ObservedObject var presetStore: PresetStore
    @ObservedObject var settings: UpscaleSettings
    let isProcessing: Bool

    @State private var newPresetName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Saved Presets", systemImage: "bookmark.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Preset name", text: $newPresetName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                            .disabled(isProcessing)

                        Button(action: savePreset) {
                            Label("Save current", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isProcessing || trimmed(newPresetName).isEmpty)
                    }

                    Text("Presets capture all current upscale settings for quick reuse.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Divider()

                    if presetStore.presets.isEmpty {
                        Text("No presets yet. Save one to reuse your favorite configuration.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(presetStore.presets) { preset in
                                PresetRow(
                                    preset: preset,
                                    isProcessing: isProcessing,
                                    onApply: { presetStore.apply(preset, to: settings) },
                                    onOverwrite: { presetStore.update(preset, settings: settings) },
                                    onRename: { newName in presetStore.update(preset, newName: newName) },
                                    onDuplicate: { presetStore.duplicate(preset) },
                                    onDelete: { presetStore.delete(preset) }
                                )
                            }
                        }
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
    }

    private func savePreset() {
        let cleaned = trimmed(newPresetName)
        guard !cleaned.isEmpty else { return }
        presetStore.add(name: cleaned, settings: settings)
        newPresetName = ""
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PresetRow: View {
    let preset: Preset
    let isProcessing: Bool
    let onApply: () -> Void
    let onOverwrite: () -> Void
    let onRename: (String) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    @State private var isRenaming = false
    @State private var nameDraft = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isRenaming {
                    TextField("Preset name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitRename)
                } else {
                    Text(preset.name)
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                Button(action: toggleRename) {
                    Image(systemName: isRenaming ? "checkmark.circle.fill" : "pencil")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }

            HStack(spacing: 8) {
                Button(action: onApply) {
                    Label("Apply", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isProcessing)

                Button(action: onOverwrite) {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isProcessing)

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive, action: { confirmDelete = true }) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.04))
        .cornerRadius(8)
        .onAppear { nameDraft = preset.name }
        .confirmationDialog("Delete preset?", isPresented: $confirmDelete) {
            Button("Delete \"\(preset.name)\"", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) { }
        }
    }

    private func toggleRename() {
        if isRenaming {
            commitRename()
        } else {
            nameDraft = preset.name
            isRenaming = true
        }
    }

    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isRenaming = false
            return
        }
        onRename(trimmed)
        isRenaming = false
    }
}

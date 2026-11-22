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
        InspectorSection(title: "Saved Presets") {
            HStack(spacing: 8) {
                TextField("Preset name", text: $newPresetName)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .disabled(isProcessing)

                Button("Save current", action: savePreset)
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || trimmed(newPresetName).isEmpty)
            }

            if let notice = presetStore.storageNotice {
                HStack(alignment: .top) {
                    InspectorNote(notice, tint: .red)
                    Button("Dismiss") { presetStore.dismissNotice() }.buttonStyle(.link)
                }
            }

            if presetStore.presets.isEmpty {
                InspectorNote("No presets yet.")
            } else {
                VStack(spacing: 12) {
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
                        .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                        .onSubmit(commitRename)
                } else {
                    Text(preset.name)
                        .font(.body)
                }

                Spacer()

                Button(isRenaming ? "Save name" : "Rename", action: toggleRename)
                    .disabled(isProcessing)
            }

            HStack(spacing: 8) {
                Button("Apply", action: onApply)
                    .disabled(isProcessing)

                Button("Update", action: onOverwrite)
                    .disabled(isProcessing)

                Button("Duplicate", action: onDuplicate)

                Button("Delete", role: .destructive, action: { confirmDelete = true })
            }
        }
        .padding(.vertical, 4)
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

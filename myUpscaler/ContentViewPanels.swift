import SwiftUI
import AppKit
struct HeaderView: View {
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                Text("MyUpscaler")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

/// Input section (drag‑drop + browse button)
struct InputSection: View {
    @Binding var inputPath: String
    let chooseInput: () -> Void
    let settings: UpscaleSettings
    var isProcessingFullUpscale: Bool = false
    var onFrameDoubleTap: ((NSImage?) -> Void)? = nil
    var onRestorationFiltersDrag: (() -> Void)? = nil
    var onColorEqualizerDrag: (() -> Void)? = nil
    var onEditorStateAvailable: ((EditorState) -> Void)? = nil
    
    var body: some View {
        MatteCardGroup(spacing: 8) {
            dragDropView()
                .frame(minHeight: 280)
                .layoutPriority(1)
        }
    }
    
    private func dragDropView() -> some View {
        DragDropView(externalInputPath: $inputPath, settings: settings, chooseInput: chooseInput, isProcessingFullUpscale: isProcessingFullUpscale, onFrameDoubleTap: onFrameDoubleTap, onRestorationFiltersDrag: onRestorationFiltersDrag, onColorEqualizerDrag: onColorEqualizerDrag, onEditorStateAvailable: onEditorStateAvailable)
            .cornerRadius(10)
            .overlay(
                // Show overlay when processing to indicate preview is frozen
                Group {
                    if isProcessingFullUpscale {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.3))
                            .overlay(
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Processing... Preview frozen")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            )
                    }
                }
            )
    }
    
}

// MARK: -  Restoration‑Filters card (denoise, deringing, sharpen)
struct RestorationFiltersPanel: View {
    @ObservedObject var settings: UpscaleSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: UI.rowSpacing) {
            HStack {
                Label("Restoration Filters", systemImage: "wand.and.stars")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)
            
            GroupBox {
                VStack(spacing: UI.rowSpacing) {
                    ParameterRow(title: "Denoise Strength",
                                 binding: $settings.denoiseStrength,
                                 range: settings.denoiseStrengthRange,
                                 step: settings.denoiseStrengthStep,
                                 defaultValue: settings.denoiseStrengthDefault,
                                 formatter: Formatters.oneFraction,
                                 sliderAccessibility: "Denoise strength slider",
                                 gradient: .denoise)
                    { _ in settings.objectWillChange.send() }
                    
                    Divider()
                    
                    // Deringing toggle + strength
                    Toggle(isOn: $settings.deringActive) {
                        Text("Deringing")
                            .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .padding(.vertical, 4)  // Add vertical padding
                    
                    if settings.deringActive {
                        ParameterRow(title: "Strength",
                                     binding: $settings.deringStrength,
                                     range: 0...10,
                                     step: 0.005,
                                     defaultValue: 0.5,
                                     formatter: Formatters.twoFraction,
                                     sliderAccessibility: "Deringing strength slider",
                                     gradient: .dering)
                        { _ in settings.objectWillChange.send() }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .padding(.top, 8)
                            .animation(.easeInOut(duration: 0.2), value: settings.deringActive)
                    }
                    
                    Divider()
                    
                    // Sharpen
                    Picker("Method", selection: $settings.sharpenMethod) {
                        Text("CAS").tag("cas")
                        Text("Unsharp Mask").tag("unsharp")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    
                    if settings.sharpenMethod == "cas" {
                        ParameterRow(title: "CAS Strength",
                                     binding: $settings.sharpenStrength,
                                     range: settings.sharpenStrengthRange,
                                     step: settings.sharpenStrengthStep,
                                     defaultValue: settings.sharpenStrengthDefault,
                                     formatter: Formatters.twoFraction,
                                     sliderAccessibility: "CAS sharpen strength slider",
                                     gradient: .sharpen)
                        { _ in settings.objectWillChange.send() }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ParameterRow(title: "Radius",
                                         binding: $settings.usmRadius,
                                         range: settings.usmRadiusRange,
                                         step: settings.usmRadiusStep,
                                         defaultValue: settings.usmRadiusDefault,
                                         formatter: Formatters.integer,
                                         sliderAccessibility: "Unsharp mask radius slider",
                                         gradient: .usmRadius)
                            { _ in settings.objectWillChange.send() }
                            
                            ParameterRow(title: "Amount",
                                         binding: $settings.usmAmount,
                                         range: settings.usmAmountRange,
                                         step: settings.usmAmountStep,
                                         defaultValue: settings.usmAmountDefault,
                                         formatter: Formatters.twoFraction,
                                         sliderAccessibility: "Unsharp mask amount slider",
                                         gradient: .usmAmount)
                            { _ in settings.objectWillChange.send() }
                            
                            ParameterRow(title: "Threshold",
                                         binding: $settings.usmThreshold,
                                         range: settings.usmThresholdRange,
                                         step: settings.usmThresholdStep,
                                         defaultValue: settings.usmThresholdDefault,
                                         formatter: Formatters.threeFraction,
                                         sliderAccessibility: "Unsharp mask threshold slider",
                                         gradient: .usmThreshold)
                            { _ in settings.objectWillChange.send() }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        .animation(.easeInOut(duration: 0.5), value: settings.deringActive)  // Animate changes
                    }
                }
                .padding(.top, 16)
            }
            .cardStyle()
        }
    }
}

// MARK: -  Restoration (First Set) panel (compact)
struct RestorationPanel: View {
    @ObservedObject var settings: UpscaleSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Restoration Filters (Extra)", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    // Deblock Mode
                    HStack {
                        Text("Deblock Mode")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.deblockMode) {
                            ForEach(settings.deblockModes, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 80)
                        TextField("Thresh", text: $settings.deblockThresh)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Deband
                    HStack {
                        Text("Deband")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.debandMethod) {
                            ForEach(settings.debandMethods, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 80)
                    }
                    
                    if settings.debandMethod == "f3kdb" {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Range")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    TextField("15", text: $settings.f3kdbRange)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 40)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Y")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    TextField("64", text: $settings.f3kdbY)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 40)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("CbCr")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    TextField("64", text: $settings.f3kdbCbCr)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 40)
                                }
                            }
                        }
                        .padding(.leading, 8)
                    } else {
                        HStack {
                            Text("Strength")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            TextField("0.015", text: $settings.debandStrength)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 55)
                        }
                        .padding(.leading, 8)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Grain Strength
                    HStack {
                        Text("Grain Strength")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("1.0", text: $settings.grainStrength)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Restoration (Second Set) panel (compact) - shown on main page
struct RestorationSecondSetPanel: View {
    @ObservedObject var settings: UpscaleSettings
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Restoration (Second Set)", systemImage: "wand.and.stars.inverse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.bottom, 4)
            GroupBox {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                            .padding(.vertical, 2)
                        
                        // Denoise 2
                        HStack {
                            Toggle(isOn: $settings.useDenoise2) {
                                Text("Denoise")
                                    .font(.caption)
                                    .foregroundColor(settings.useDenoise2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            if settings.useDenoise2 {
                                Spacer()
                                Picker("", selection: $settings.denoiser2) {
                                    ForEach(settings.denoisers, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 70)
                                TextField("Str", text: $settings.denoiseStrength2)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                
                                // Show effective value if attenuated
                                if settings.isDenoiseStacked {
                                    Text("→\(settings.effectiveDenoiseStrength2)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.orange)
                                }
                            } else {
                                Spacer()
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        // Deringing 2
                        HStack {
                            Toggle(isOn: $settings.useDering2) {
                                Text("Deringing")
                                    .font(.caption)
                                    .foregroundColor(settings.useDering2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            if settings.useDering2 {
                                Spacer()
                                Toggle(isOn: $settings.deringActive2) {
                                    Text("On")
                                        .font(.system(size: 10))
                                }
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                
                                if settings.deringActive2 {
                                    TextField("0.5", text: $settings.deringStrength2)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 45)
                                }
                            } else {
                                Spacer()
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        // Sharpen 2
                        HStack {
                            Toggle(isOn: $settings.useSharpen2) {
                                Text("Sharpen")
                                    .font(.caption)
                                    .foregroundColor(settings.useSharpen2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            if settings.useSharpen2 {
                                Spacer()
                                Picker("", selection: $settings.sharpenMethod2) {
                                    ForEach(settings.sharpenMethods, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 90)
                            } else {
                                Spacer()
                            }
                        }
                        
                        if settings.useSharpen2 {
                            if settings.sharpenMethod2 == "unsharp" {
                                HStack(spacing: 6) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("R")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("5", text: $settings.usmRadius2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("A")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("1.0", text: $settings.usmAmount2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("T")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("0.03", text: $settings.usmThreshold2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 40)
                                    }
                                    
                                    // Show effective values if attenuated
                                    if settings.isSharpenStacked {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("→")
                                                .font(.system(size: 9))
                                                .foregroundColor(.orange)
                                            Text("\(settings.effectiveUsmAmount2)")
                                                .font(.system(size: 9))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                .padding(.leading, 8)
                            } else {
                                HStack {
                                    Text("CAS")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("0.25", text: $settings.sharpenStrength2)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 50)
                                    
                                    // Show effective value if attenuated
                                    if settings.isSharpenStacked {
                                        Text("→\(settings.effectiveSharpenStrength2)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.leading, 8)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        // Deband 2
                        HStack {
                            Toggle(isOn: $settings.useDeband2) {
                                Text("Deband")
                                    .font(.caption)
                                    .foregroundColor(settings.useDeband2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            if settings.useDeband2 {
                                Spacer()
                                Picker("", selection: $settings.debandMethod2) {
                                    ForEach(settings.debandMethods, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .controlSize(.small)
                                .frame(width: 70)
                            } else {
                                Spacer()
                            }
                        }
                        
                        if settings.useDeband2 {
                            if settings.debandMethod2 == "f3kdb" {
                                HStack(spacing: 6) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Range")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("15", text: $settings.f3kdbRange2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Y")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("64", text: $settings.f3kdbY2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("CbCr")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        TextField("64", text: $settings.f3kdbCbCr2)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 35)
                                    }
                                }
                                .padding(.leading, 8)
                            } else {
                                HStack {
                                    Text("Strength")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("0.015", text: $settings.debandStrength2)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 55)
                                }
                                .padding(.leading, 8)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        // Grain 2
                        HStack {
                            Toggle(isOn: $settings.useGrain2) {
                                Text("Grain")
                                    .font(.caption)
                                    .foregroundColor(settings.useGrain2 ? .primary : .secondary)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            if settings.useGrain2 {
                                Spacer()
                                TextField("1.0", text: $settings.grainStrength2)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                            } else {
                                Spacer()
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    
                    
                    // Filter stacking indicator
                    if settings.hasFilterStacking {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 10))
                            Text("Smart Attenuation")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange.opacity(0.15))
                        )
                    }
                }
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .cardStyle()
        }
    }
}

// MARK: - x265 Parameters panel (compact)
struct X265ParametersPanel: View {
    @ObservedObject var settings: UpscaleSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("x265 Parameters", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        // AQ Mode
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AQ Mode")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            TextField("3", text: $settings.x265AqMode)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                        }
                        
                        // Psy-RD
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Psy-RD")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            TextField("2.0", text: $settings.x265PsyRd)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                        }
                        
                        // Deblock
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Deblock")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                TextField("-2", text: $settings.x265Deblock1)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 35)
                                Text(",")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("-2", text: $settings.x265Deblock2)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 35)
                            }
                        }
                        
                        Spacer()
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}


// MARK: -  Hardware & Encoding panel (compact)
struct HardwareEncodingPanel: View {
    @ObservedObject var settings: UpscaleSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Hardware & Encoding", systemImage: "gearshape.2")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    // HW Acceleration
                    HStack {
                        Text("HW Acceleration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.hwAccel) {
                            ForEach(settings.hwAccels, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Encoder
                    HStack {
                        Text("Encoder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.encoder) {
                            ForEach(settings.encoders, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Toggles
                    VStack(spacing: 6) {
                        HStack(spacing: 12) {
                            Toggle(isOn: $settings.useHEVC) {
                                Text("Use HEVC (H.265)")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            Toggle(isOn: $settings.use10Bit) {
                                Text("10‑Bit Output")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            
                            // MOV Faststart Toggle
                            Toggle(isOn: Binding(
                                get: { settings.movflags.contains("+faststart") },
                                set: { isEnabled in
                                    if isEnabled {
                                        if !settings.movflags.contains("+faststart") {
                                            if settings.movflags.isEmpty {
                                                settings.movflags = "+faststart"
                                            } else {
                                                settings.movflags += " +faststart"
                                            }
                                        }
                                    } else {
                                        settings.movflags = settings.movflags.replacingOccurrences(of: "+faststart", with: "").trimmingCharacters(in: .whitespaces)
                                    }
                                }
                            )) {
                                Text("Faststart")
                                    .font(.caption)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .help("Moves metadata to the beginning of the file for faster web playback")
                            
                            Spacer()
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        HStack {
                           Text("Audio Bitrate")
                               .font(.caption)
                               .foregroundColor(.secondary)
                           Spacer()
                           TextField("192k", text: $settings.audioBitrate)
                               .textFieldStyle(.roundedBorder)
                               .frame(width: 60)
                       }

                        #if arch(arm64)
                        Text("VideoToolbox decode")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        #else
                        Text("If hardware decode fails, set HW Acceleration to None.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        #endif
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    HStack {
                        Text("Preset")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.preset) {
                            ForEach(settings.presets, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    HStack {
                        Text("Threads")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("0 (auto)", text: $settings.threads)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Output panel (compact, destination picker + preview name)
struct OutputPanel: View {
    @Binding var outputMode: UpscaleRunner.OutputMode
    @Binding var customOutputFolder: String
    let predictedName: String
    let chooseFolder: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Output", systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $outputMode) {
                            Text("Same folder").tag(UpscaleRunner.OutputMode.same)
                            Text("Custom folder").tag(UpscaleRunner.OutputMode.custom)
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 120)
                        .fixedSize()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: outputMode)
                    }
                    
                    if outputMode == .custom {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                            Text(customOutputFolder)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                            Spacer()
                            
                            Button("Choose", action: chooseFolder)
                                .controlSize(.mini)
                                .dynamicKeyboardShortcut(actionId: "chooseOutput", action: chooseFolder)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .background(cardBackground)  // background to see easier
                        .cornerRadius(6)
                        .zIndex(1)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 10))
                        Text("Will output:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(predictedName)
                            .font(.system(size: 9))
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Run / Cancel buttons
struct ActionButtons: View {
    @ObservedObject var runner: UpscaleRunner
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: runner.run) {
                HStack {
                    if runner.isRunning {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(runner.isRunning ? "Processing…" : "Run Upscaler")
                }
                .frame(maxWidth: .infinity)
            }
            
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .frame(height: UI.buttonHeight)
            .disabled(runner.isRunning || runner.inputPath.isEmpty)
            .dynamicKeyboardShortcut(actionId: "runUpscaler") {
                if !runner.isRunning && !runner.inputPath.isEmpty { runner.run() }
            }
            
            Button(action: runner.cancel) {
                Label("Cancel", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .frame(height: UI.buttonHeight)
            .disabled(!runner.isRunning)
            .dynamicKeyboardShortcut(actionId: "cancel") {
                if runner.isRunning { runner.cancel() }
            }
        }
    }
}

/// Progress bar + FPS / time / ETA line
struct ProgressDetails: View {
    @ObservedObject var runner: UpscaleRunner
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: runner.progress)
                .tint(.accentColor)
                .frame(height: 4)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)// slim native bar
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 14) {
                Label(runner.fpsString, systemImage: "gauge")
                Label(runner.timeString, systemImage: "clock")
                Label(runner.etaString, systemImage: "hourglass")
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.accentColor.opacity(0.07))
        .cornerRadius(6)
    }
}

// MARK: -  : Processing Log (UI)
struct LogPanel: View {
    @ObservedObject var runner: UpscaleRunner
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Processing Log", systemImage: "text.bubble")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    ScrollViewReader { reader in
                        ScrollView {
                            Text(runner.log.isEmpty ? "Waiting to start processing…" : runner.log)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(6)                      // tight inner padding
                                .id("BOTTOM")
                        }
                        .padding(.vertical, 30)  // Add this
                        .onChange(of: runner.log) { _, _ in
                            withAnimation { reader.scrollTo("BOTTOM", anchor: .bottom) }
                            
                            // Check for completion when log updates
                            if !runner.isRunning {
                                runner.checkForCompletedOutput()
                            }
                        }
                        .onChange(of: runner.isRunning) { _, isRunning in
                            // When processing stops, check for output file
                            if !isRunning {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    runner.checkForCompletedOutput()
                                }
                            }
                        }
                    }
                    .frame(height: 170) 
                    
                    if !runner.isRunning, let outputPath = runner.completedOutputPath {
                        if FileManager.default.fileExists(atPath: outputPath),
                           let attributes = try? FileManager.default.attributesOfItem(atPath: outputPath),
                           let fileSize = attributes[.size] as? Int64,
                           fileSize > 0 {
                            Divider()
                                .padding(.vertical, 4)
                            
                            HStack(spacing: 8) {
                                Button(action: {
                                    openVideoFile(at: outputPath)
                                }) {
                                    HStack {
                                        Image(systemName: "play.circle.fill")
                                        Text("Open")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                Button(action: {
                                    revealVideoFile(at: outputPath)
                                }) {
                                    HStack {
                                        Image(systemName: "folder")
                                        Text("Reveal in Finder")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
        .onChange(of: runner.inputPath) { _, _ in
            runner.completedOutputPath = nil
        }
    }
    
    // Note: sandbox requirement securityScopedOutputURL
    private func openVideoFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        var needsStopAccess = false
        if let scopedURL = runner.securityScopedOutputURL {
            needsStopAccess = scopedURL.startAccessingSecurityScopedResource()
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let scopedURL = runner.securityScopedOutputURL
        
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if needsStopAccess, let url = scopedURL {
                url.stopAccessingSecurityScopedResource()
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    print("Failed to open video: \(error.localizedDescription)")
                    let alert = NSAlert()
                    alert.informativeText = "No path permission, revealed in Finder instead."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                    
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }
    
    private func revealVideoFile(at path: String) {
        // Revealing in Finder works reliably under sandbox
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

// MARK: -  Saved presets management panel
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

// MARK: -  Single preset row with actions
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
// MARK: -  Quality & Scale panel (compact)
struct QualityScalePanel: View {
    @ObservedObject var settings: UpscaleSettings
    @State private var localCRF: Double? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Quality & Scale", systemImage: "chart.bar")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    // CRF Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("CRF")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(localCRF ?? settings.crf))")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.primary)
                            Text("(Lower is better)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        LuxuriousSlider(value: Binding(
                            get: { localCRF ?? settings.crf },
                            set: { localCRF = $0 }
                        ), range: 0...51, step: 1, gradient: .crf, onEditingChanged: { editing in
                            if !editing {
                                if let finalValue = localCRF {
                                    settings.crf = finalValue
                                    localCRF = nil
                                }
                            }
                        })
                        .frame(minWidth: 100)
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Scale Factor and FPS
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scale")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("2.0", value: $settings.scaleFactor, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FPS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("60", text: $settings.fps)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    // Interpolation Mode
                    HStack {
                        Text("Interpolation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.interpolation) {
                            ForEach(settings.interpolations, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: -  AI Engine panel (compact)
struct AIEnginePanel: View {
    @ObservedObject var settings: UpscaleSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("AI Engine", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            GroupBox {
                VStack(spacing: 8) {
                    // Scaler
                    HStack {
                        Text("Scaler")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: $settings.scaler) {
                            ForEach(settings.scalers, id: \.self) { Text($0) }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(width: 100)
                    }
                    
                    if settings.scaler == "coreml" {
                        Divider()
                            .padding(.vertical, 2)
                        
                        HStack {
                            Text("CoreML Model")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.coremlModelId) {
                                ForEach(settings.coremlModels) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 140)
                        }
                    }
                    
                    if settings.scaler == "ai" {
                        Divider()
                            .padding(.vertical, 2)
                        
                        // AI Backend
                        HStack {
                            Text("AI Backend")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.aiBackend) {
                                ForEach(settings.aiBackends, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 100)
                        }
                        
                        // DNN Backend
                        HStack {
                            Text("DNN Backend")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.dnnBackend) {
                                ForEach(settings.dnnBackends, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 100)
                        }
                        
                        // Model Type
                        HStack {
                            Text("Model Type")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: $settings.aiModelType) {
                                ForEach(settings.aiModelTypes, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 100)
                        }
                        
                        Divider()
                            .padding(.vertical, 2)
                        
                        // Model Path
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Model Path")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                TextField("", text: $settings.aiModelPath)
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse") {
                                    let panel = NSOpenPanel()
                                    panel.allowsMultipleSelection = false
                                    if panel.runModal() == .OK, let url = panel.url {
                                        settings.aiModelPath = url.path
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(8)
            }
            .cardStyle()
        }
        .frame(maxWidth: .infinity)
    }
}
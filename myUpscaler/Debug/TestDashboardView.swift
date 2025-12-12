import SwiftUI
import Combine

#if DEBUG

enum DashboardMode {
    case beginner
    case developer
}

struct TestDashboardView: View {
    @StateObject private var vm = TestDashboardViewModel()
    @State private var mode: DashboardMode = .beginner
    
    var body: some View {
        VStack {
            HStack {
                Text("Test Dashboard")
                    .font(.largeTitle)
                Spacer()
                Picker("Mode", selection: $mode) {
                    Text("Beginner").tag(DashboardMode.beginner)
                    Text("Developer").tag(DashboardMode.developer)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding()
            
            HStack {
                Button("Run Fuzzer") {
                    Task { await vm.runFuzzer() }
                }
                .disabled(vm.isRunning)
                
                Button("Run Performance") {
                    Task { await vm.runPerformance() }
                }
                .disabled(vm.isRunning)
            }
            .padding()
            
            if vm.isRunning {
                ProgressView("Running Tests...")
                    .padding()
            }
            
            List {
                if let result = vm.lastResult {
                    Section(header: resultHeader(result)) {
                        if mode == .beginner {
                            beginnerView(result)
                        } else {
                            developerView(result)
                        }
                    }
                } else {
                    Text("No results yet.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    // MARK: - Components
    
    private func resultHeader(_ result: TestResult) -> some View {
        HStack {
            Text("\(result.scenarioName)")
                .font(.headline)
            Spacer()
            if result.passed {
                Label("Passed", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Label("Failed (\(result.failureCount) errors)", systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            Text(String(format: "%.2fs", result.duration))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func beginnerView(_ result: TestResult) -> some View {
        ForEach(result.events) { event in
            // Only show relevant items for beginners (failures or significant events)
            if !event.isValid || event.complexity == .beginner {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: event.isValid ? "checkmark.circle" : "exclamationmark.triangle.fill")
                            .foregroundColor(event.isValid ? .green : .orange)
                        Text(event.parameter)
                            .bold()
                    }
                    
                    if let explanation = event.explanation {
                        Text(explanation.simpleSummary)
                            .font(.body)
                        Text("Why: " + explanation.detailedReason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if !event.isValid {
                            Text("Fix: " + explanation.suggestedFix)
                                .font(.caption)
                                .bold()
                                .foregroundColor(.blue)
                        }
                    } else {
                        Text(event.error ?? "Unknown status")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func developerView(_ result: TestResult) -> some View {
        ForEach(result.events) { event in
            VStack(alignment: .leading) {
                HStack {
                    Text("[\(event.toolName)]")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(event.parameter)
                        .bold()
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(event.isValid ? "OK" : "FAIL")
                        .font(.caption)
                        .foregroundColor(event.isValid ? .green : .red)
                        .padding(2)
                        .background(event.isValid ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
                
                HStack {
                    Text("\(event.beforeValue)")
                        .strikethrough()
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                    Text("\(event.afterValue)")
                }
                .font(.caption)
                
                if let error = event.error {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if let explanation = event.explanation {
                    Text("Exp: \(explanation.detailedReason)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

class TestDashboardViewModel: ObservableObject {
    @Published var lastResult: TestResult?
    @Published var isRunning = false
    
    @MainActor
    func runFuzzer() async {
        isRunning = true
        defer { isRunning = false }
        
        let start = Date()
        let fuzzer = SettingsFuzzer()
        var result = await fuzzer.run()
        result.duration = Date().timeIntervalSince(start)
        
        // Enrich with explanations for demo purposes if missing
        result.events = result.events.map { event in
            if !event.isValid && event.explanation == nil {
                return TestEvent.boundaryError(
                    parameter: event.parameter,
                    value: event.afterValue,
                    min: "0.0",
                    max: "10.0" // Generic range for demo
                )
            }
            return event
        }
        
        self.lastResult = result
        saveReport(result)
    }
    
    @MainActor
    func runPerformance() async {
        isRunning = true
        defer { isRunning = false }
        
        var result = TestResult(scenarioName: "Performance Check")
        let start = Date()
        
        // Simulate load
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Log throughput check
        let throughput = runThroughputBenchmark()
        result.events.append(
            TestEvent(
                toolName: "LogParser",
                parameter: "Throughput",
                beforeValue: "-",
                afterValue: "\(Int(throughput)) lines/s",
                isValid: true,
                complexity: .expert
            )
        )
        
        result.duration = Date().timeIntervalSince(start)
        self.lastResult = result
        saveReport(result)
    }
    
    func runThroughputBenchmark() -> Double {
        let start = Date()
        let iterations = 10_000
        let testDuration: Double = 10.0 // Duration in seconds matching the test time string
        
        for i in 0..<iterations {
            _ = FFmpegParser.parse(line: "frame= \(i) fps=60.0 time=00:00:10.00", currentDuration: testDuration)
        }
        
        let elapsed = Date().timeIntervalSince(start)
        return Double(iterations) / elapsed
    }
    
    func saveReport(_ result: TestResult) {
        let fm = FileManager.default
        let dateParams = DateFormatter()
        dateParams.dateFormat = "yyyy-MM-dd"
        let dateStr = dateParams.string(from: Date())
        
        // Use document directory for sandboxed app
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let reportsDir = docs.appendingPathComponent("Tests/Reports/\(dateStr)")
        
        try? fm.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(result) {
            let filename = "report_\(Int(Date().timeIntervalSince1970)).json"
            try? data.write(to: reportsDir.appendingPathComponent(filename))
            print("Saved report to \(reportsDir.appendingPathComponent(filename))")
        }
    }
}

#endif

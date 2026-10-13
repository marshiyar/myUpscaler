import Foundation

extension UpscaleRunner {
    nonisolated static func makeBatchPlan(input: String, output: String, coreML: Bool) async throws -> BatchPlan {
        let task = Task.detached(priority: .userInitiated) {
            try BatchPlan.make(input: URL(fileURLWithPath: input), outputFolder: URL(fileURLWithPath: output), coreML: coreML)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    func processBatch(_ plan: BatchPlan, engine: EngineProtocol, settings: UpscaleSettings) async throws {
        log.append("Batch plan: \(plan.items.count) files → \(plan.outputRoot.path)\n")
        for (index, item) in plan.items.enumerated() {
            try Task.checkCancellation()
            try BatchPlan.checkDestination(item.output, root: plan.outputRoot)
            let parent = item.output.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            // Engines may replace files only inside this job-owned temporary directory.
            let temporary = parent.appendingPathComponent(".myUpscaler-batch-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: temporary) }
            phase = .processing
            progressKnown = true
            log.append("[\(index + 1)/\(plan.items.count)] \(item.input.path)\n")
            do {
                try await engine.process(inputPath: item.input.path, settings: settings, outputDirectory: temporary.path)
                try Task.checkCancellation()
                let staged = temporary.appendingPathComponent(item.output.lastPathComponent)
                let attributes = try FileManager.default.attributesOfItem(atPath: staged.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
                    throw Up60PEngineError.io
                }
                try BatchPlan.checkDestination(item.output, root: plan.outputRoot)
                try BatchPlan.commit(staged: staged, output: item.output)
                batchCompleted += 1
                progress = Double(batchCompleted) / Double(plan.items.count)
                log.append("Completed: \(item.output.path)\n")
            } catch {
                log.append("Batch stopped at \(item.input.path); \(batchCompleted)/\(plan.items.count) files completed.\n")
                throw error
            }
        }
    }
}

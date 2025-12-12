import Foundation

/// Defines difficulty and target audience for a test event
enum TestComplexity: String, Codable {
    case beginner
    case advanced
    case expert
}

/// Provides user-friendly explanations for technical errors
struct BeginnerExplanation: Codable {
    let simpleSummary: String
    let detailedReason: String
    let suggestedFix: String
}

/// Records a specific test event, such as a value change or an error
struct TestEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let toolName: String
    let parameter: String
    let beforeValue: String
    let afterValue: String
    let isValid: Bool
    let error: String?
    let complexity: TestComplexity
    let explanation: BeginnerExplanation?
    
    // Visual trace support
    let imageBefore: String? // Path or asset name
    let imageAfter: String?  // Path or asset name
    
    init(
        toolName: String,
        parameter: String,
        beforeValue: String,
        afterValue: String,
        isValid: Bool,
        error: String? = nil,
        complexity: TestComplexity = .advanced,
        explanation: BeginnerExplanation? = nil,
        imageBefore: String? = nil,
        imageAfter: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.toolName = toolName
        self.parameter = parameter
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.isValid = isValid
        self.error = error
        self.complexity = complexity
        self.explanation = explanation
        self.imageBefore = imageBefore
        self.imageAfter = imageAfter
    }
}

/// Aggregates results from a test run
struct TestResult: Identifiable, Codable {
    let id: UUID
    let scenarioName: String
    let timestamp: Date
    var duration: TimeInterval
    var events: [TestEvent]
    var passed: Bool
    
    // Summary statistics
    var failureCount: Int { events.filter { !$0.isValid }.count }
    var warningCount: Int { 0 } // Future use
    
    init(scenarioName: String) {
        self.id = UUID()
        self.scenarioName = scenarioName
        self.timestamp = Date()
        self.duration = 0
        self.events = []
        self.passed = true
    }
}

/// Protocol defining a test scenario (e.g., Fuzzing, Regression)
protocol TestScenario {
    var name: String { get }
    var description: String { get }
    func run() async -> TestResult
}

// MARK: - Beginner Friendly Helpers

extension TestEvent {
    static func boundaryError(parameter: String, value: String, min: String, max: String) -> TestEvent {
        return TestEvent(
            toolName: "Settings Validation",
            parameter: parameter,
            beforeValue: "?",
            afterValue: value,
            isValid: false,
            error: "Value out of bounds",
            complexity: .beginner,
            explanation: BeginnerExplanation(
                simpleSummary: "The setting '\(parameter)' is too high or too low.",
                detailedReason: "The value \(value) is outside the allowed range of \(min) to \(max). Setting it this way could crash the engine.",
                suggestedFix: "Move the slider back to within the green zone (\(min)-\(max))."
            )
        )
    }
    
    static func conflictError(parameter: String, conflictsWith: String) -> TestEvent {
        return TestEvent(
            toolName: "Compatibility Check",
            parameter: parameter,
            beforeValue: "Enabled",
            afterValue: "Enabled",
            isValid: false,
            error: "Parameter Conflict",
            complexity: .beginner,
            explanation: BeginnerExplanation(
                simpleSummary: "These two settings don't work together.",
                detailedReason: "'\(parameter)' cannot be used at the same time as '\(conflictsWith)' because they try to modify the same part of the video pipeline.",
                suggestedFix: "Turn off one of them."
            )
        )
    }
}

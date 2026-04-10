import Foundation

struct PracticeAttempt: Identifiable, Equatable {
    let id: UUID
    var backendAttemptID: String?
    let recordingReference: String
    var analysis: PracticeAnalysis?

    init(
        id: UUID = UUID(),
        backendAttemptID: String? = nil,
        recordingReference: String,
        analysis: PracticeAnalysis? = nil
    ) {
        self.id = id
        self.backendAttemptID = backendAttemptID
        self.recordingReference = recordingReference
        self.analysis = analysis
    }
}

enum LocalRecordingDraftState: Equatable {
    case recording
    case stopped
}

struct LocalRecordingDraft: Equatable {
    let recordingReference: String
    var state: LocalRecordingDraftState
}

struct PracticeSession: Equatable {
    let quote: Quote
    var backendSessionID: String?
    var attempts: [PracticeAttempt]
    var localRecordingDraft: LocalRecordingDraft?

    init(
        quote: Quote,
        backendSessionID: String? = nil,
        attempts: [PracticeAttempt] = [],
        localRecordingDraft: LocalRecordingDraft? = nil
    ) {
        self.quote = quote
        self.backendSessionID = backendSessionID
        self.attempts = attempts
        self.localRecordingDraft = localRecordingDraft
    }

    var latestAttempt: PracticeAttempt? {
        attempts.last
    }

    var latestAnalysis: PracticeAnalysis? {
        latestAttempt?.analysis
    }

    var hasAttemptHistory: Bool {
        !attempts.isEmpty
    }

    var hasLocalRecordingDraft: Bool {
        localRecordingDraft != nil
    }
}

enum MainSessionState: Equatable {
    case start
    case practice(PracticeSession)

    var selectedQuote: Quote? {
        practiceSession?.quote
    }

    var isPractice: Bool {
        practiceSession != nil
    }

    var practiceSession: PracticeSession? {
        guard case let .practice(session) = self else {
            return nil
        }

        return session
    }
}

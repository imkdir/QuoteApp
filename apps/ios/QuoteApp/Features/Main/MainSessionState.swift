import Foundation

struct PracticeAttempt: Identifiable, Equatable {
    let id: UUID
    let recordingReference: String
    var analysis: PracticeAnalysis?

    init(id: UUID = UUID(), recordingReference: String, analysis: PracticeAnalysis? = nil) {
        self.id = id
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
    var attempts: [PracticeAttempt]
    var localRecordingDraft: LocalRecordingDraft?

    init(quote: Quote, attempts: [PracticeAttempt] = [], localRecordingDraft: LocalRecordingDraft? = nil) {
        self.quote = quote
        self.attempts = attempts
        self.localRecordingDraft = localRecordingDraft
    }

    var latestAttempt: PracticeAttempt? {
        attempts.last
    }

    var latestAnalysis: PracticeAnalysis? {
        latestAttempt?.analysis
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

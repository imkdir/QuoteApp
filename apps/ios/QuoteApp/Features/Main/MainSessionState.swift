import Foundation

struct PracticeAttempt: Identifiable, Equatable {
    let id: UUID
    var backendAttemptID: String?
    var recordingReference: String
    var analysis: PracticeAnalysis?
    var isSupersededForUI: Bool

    init(
        id: UUID = UUID(),
        backendAttemptID: String? = nil,
        recordingReference: String,
        analysis: PracticeAnalysis? = nil,
        isSupersededForUI: Bool = false
    ) {
        self.id = id
        self.backendAttemptID = backendAttemptID
        self.recordingReference = recordingReference
        self.analysis = analysis
        self.isSupersededForUI = isSupersededForUI
    }
}

enum LocalRecordingDraftState: Equatable {
    case recording
    case stopped
}

struct LocalRecordingDraft: Equatable {
    var recordingReference: String
    var state: LocalRecordingDraftState
}

struct PracticeSession: Equatable {
    let quote: Quote
    var backendSessionID: String?
    var liveKitRoomName: String?
    var tutorPlaybackIdentity: String?
    var attempts: [PracticeAttempt]
    var localRecordingDraft: LocalRecordingDraft?

    init(
        quote: Quote,
        backendSessionID: String? = nil,
        liveKitRoomName: String? = nil,
        tutorPlaybackIdentity: String? = nil,
        attempts: [PracticeAttempt] = [],
        localRecordingDraft: LocalRecordingDraft? = nil
    ) {
        self.quote = quote
        self.backendSessionID = backendSessionID
        self.liveKitRoomName = liveKitRoomName
        self.tutorPlaybackIdentity = tutorPlaybackIdentity
        self.attempts = attempts
        self.localRecordingDraft = localRecordingDraft
    }

    var latestAttempt: PracticeAttempt? {
        attempts.last
    }

    var latestAnalysis: PracticeAnalysis? {
        latestAttempt?.analysis
    }

    var hasLocalRecordingDraft: Bool {
        localRecordingDraft != nil
    }

    var isInRecordingExclusiveMode: Bool {
        hasLocalRecordingDraft
    }

    var quoteWordCount: Int {
        quote.wordCount
    }
}

enum MainSessionState: Equatable {
    case start
    case practice(PracticeSession)

    var selectedQuote: Quote? {
        practiceSession?.quote
    }

    var selectedQuoteWordCount: Int {
        selectedQuote?.wordCount ?? 0
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

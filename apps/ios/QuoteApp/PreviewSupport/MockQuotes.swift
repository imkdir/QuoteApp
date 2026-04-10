import Foundation

enum MockQuotes {
    static let all: [Quote] = [
        Quote(
            id: "gatsby-01",
            previewText: "So we beat on, boats against the current...",
            fullText: "So we beat on, boats against the current, borne back ceaselessly into the past.",
            bookTitle: "The Great Gatsby",
            author: "F. Scott Fitzgerald",
            mockMarkedNormalizedTokens: ["boats", "ceaselessly", "past"]
        ),
        Quote(
            id: "jane-eyre-01",
            previewText: "I am no bird; and no net ensnares me...",
            fullText: "I am no bird; and no net ensnares me: I am a free human being with an independent will.",
            bookTitle: "Jane Eyre",
            author: "Charlotte Bronte",
            mockMarkedNormalizedTokens: ["ensnares", "independent", "will"]
        ),
        Quote(
            id: "hamlet-01",
            previewText: "There is nothing either good or bad, but thinking makes it so.",
            fullText: "There is nothing either good or bad, but thinking makes it so.",
            bookTitle: "Hamlet",
            author: "William Shakespeare",
            mockMarkedNormalizedTokens: ["thinking", "good", "bad"]
        ),
        Quote(
            id: "pride-01",
            previewText: "I could easily forgive his pride, if he had not mortified mine.",
            fullText: "I could easily forgive his pride, if he had not mortified mine.",
            bookTitle: "Pride and Prejudice",
            author: "Jane Austen",
            mockMarkedNormalizedTokens: ["forgive", "pride", "mortified"]
        )
    ]
}

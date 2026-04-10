import Foundation

struct Quote: Identifiable, Hashable {
    let id: String
    let previewText: String
    let fullText: String
    let bookTitle: String
    let author: String
}

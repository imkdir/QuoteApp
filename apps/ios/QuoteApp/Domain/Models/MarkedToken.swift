import Foundation

struct MarkedToken: Identifiable, Hashable {
    let index: Int
    let normalizedText: String

    var id: String { "\(index)-\(normalizedText)" }
}

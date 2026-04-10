import Foundation

enum MainSessionState: Equatable {
    case start
    case practice(Quote)

    var selectedQuote: Quote? {
        guard case let .practice(quote) = self else {
            return nil
        }

        return quote
    }
}

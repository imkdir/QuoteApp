import SwiftUI

@MainActor
struct RootView: View {
    private let viewModel: MainViewModel

    init() {
        self.viewModel = .runtime()
    }

    init(viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        MainScreen(viewModel: viewModel)
    }
}

#if DEBUG
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView(viewModel: .previewStart)
    }
}
#endif

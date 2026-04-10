import SwiftUI

struct RootView: View {
    var body: some View {
        MainScreen()
    }
}

#if DEBUG
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}
#endif

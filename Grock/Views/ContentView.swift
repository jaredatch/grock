import SwiftUI

/// Preview / future companion host. The overlay panel uses the WKWebView directly.
struct ContentView: View {
    var body: some View {
        GrokWebView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 600)
}

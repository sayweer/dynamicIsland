import Combine
import SwiftUI
import WebKit

/// In-notch mini browser backed by a persistent WKWebView.
@MainActor
final class BrowserModel: ObservableObject {
    @Published var addressText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var hasPage = false

    let webView: WKWebView
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        webView.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isLoading = $0 }
            .store(in: &cancellables)
        webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canGoBack = $0 }
            .store(in: &cancellables)
        webView.publisher(for: \.canGoForward)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canGoForward = $0 }
            .store(in: &cancellables)
        webView.publisher(for: \.url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                guard let self else { return }
                self.hasPage = url != nil
                if let url { self.addressText = url.absoluteString }
            }
            .store(in: &cancellables)
    }

    func submit() {
        let text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        load(text)
    }

    func load(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let urlString: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            urlString = trimmed
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            urlString = "https://" + trimmed
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            urlString = "https://www.google.com/search?q=\(query)"
        }
        guard let url = URL(string: urlString) else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func openInDefaultBrowser() {
        guard let url = webView.url else { return }
        NSWorkspace.shared.open(url)
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

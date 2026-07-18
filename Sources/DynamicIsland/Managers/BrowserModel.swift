import Combine
import SwiftUI
import WebKit

/// In-notch mini browser backed by a persistent WKWebView.
@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published var addressText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var hasPage = false
    /// Son yükleme hatayla bitti (ağ yok, DNS hatası vb.) — UI hata durumu gösterir.
    @Published private(set) var loadFailed = false
    /// Adres çubuğu odaktayken URL değişimleri (redirect, geç yükleme) kullanıcının
    /// yazmakta olduğu metni ezmesin. View odak durumunu buraya yansıtır.
    var isEditingAddress = false

    let webView: WKWebView
    private var cancellables: Set<AnyCancellable> = []
    /// Yeniden dene için: provizyonel yükleme başarısız olduğunda `webView.url`
    /// hâlâ eski sayfayı (veya nil) gösterir; hedefi ayrıca saklarız.
    private var lastRequestedURL: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self

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
                if let url, !self.isEditingAddress {
                    self.addressText = url.absoluteString
                }
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
            // .urlQueryAllowed '&', '+', '=' karakterlerini kaçışlamaz; sorgu
            // parametresi bölünür ("fish & chips" → yanlış arama). Yalnızca
            // güvenli karakterleri bırakıp gerisini yüzde-kodluyoruz.
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
            urlString = "https://www.google.com/search?q=\(query)"
        }
        guard let url = URL(string: urlString) else { return }
        lastRequestedURL = url
        loadFailed = false
        webView.load(URLRequest(url: url))
    }

    func retry() {
        loadFailed = false
        if let url = lastRequestedURL {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func openInDefaultBrowser() {
        guard let url = webView.url else { return }
        NSWorkspace.shared.open(url)
    }
}

extension BrowserModel: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in self.loadFailed = false }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleFailure(error)
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    nonisolated private func handleFailure(_ error: Error) {
        // Kullanıcı hızlıca yeni bir adrese geçince iptal edilen yükleme hata değildir.
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        Task { @MainActor in self.loadFailed = true }
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

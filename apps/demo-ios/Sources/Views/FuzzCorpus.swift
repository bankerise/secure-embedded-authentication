import Foundation

/// Hardcoded hostile-URL corpus for the §23.2 navigation-fuzzing manual check.
///
/// IMPORTANT — contract note (see README "Fuzz screen vs §7.3 navigation policy"):
/// the Phase-1 core contract (docs/api-contract-ios-v1.md) exposes exactly one
/// public validation entry point, `SEAAuthorizeURLValidator.validate` (§5). The
/// full in-WebView navigation policy (§6 of the contract / spec §7.3) — which is
/// what actually decides allow/block for a URL the WebView is mid-navigation to —
/// is implemented inside SEACore's WKNavigationDelegate and is NOT exposed as a
/// standalone callable API. Since this corpus is evaluated *before* any session
/// starts (there is no WebView to navigate), we run every entry through the one
/// exposed validator. In practice the two policies agree on every entry in this
/// corpus (scheme/host/userinfo/length rules are shared), but this is calling
/// the authorize-URL gate, not the live navigation-delegate code path — flagged
/// here and in the report as a contract ambiguity, not silently papered over.
struct FuzzCorpusEntry: Identifiable {
    let id = UUID()
    let label: String
    let urlString: String
}

enum FuzzCorpus {
    static let entries: [FuzzCorpusEntry] = {
        let overlongQuery = String(repeating: "a=1&", count: 600) // » 2 KB
        return [
            FuzzCorpusEntry(label: "javascript: scheme", urlString: "javascript:alert(1)"),
            FuzzCorpusEntry(
                label: "intent: scheme",
                urlString: "intent://evil/#Intent;scheme=http;package=com.evil;end"
            ),
            FuzzCorpusEntry(label: "file: scheme", urlString: "file:///etc/passwd"),
            FuzzCorpusEntry(label: "plain http (not https)", urlString: "http://auth.bank.local"),
            FuzzCorpusEntry(label: "look-alike host (hyphen prefix)", urlString: "https://evil-auth.bank.local"),
            FuzzCorpusEntry(label: "look-alike host (suffix trick)", urlString: "https://auth.bank.local.evil.io"),
            FuzzCorpusEntry(label: "userinfo trick", urlString: "https://auth.bank.local@evil.io/"),
            FuzzCorpusEntry(label: "data: scheme", urlString: "data:text/html,<script>alert(1)</script>"),
            FuzzCorpusEntry(label: "oversized URL (>2KB)", urlString: "https://auth.bank.local/?\(overlongQuery)"),
        ]
    }()
}

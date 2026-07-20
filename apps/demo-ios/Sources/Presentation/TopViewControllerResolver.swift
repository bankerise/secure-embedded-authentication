import UIKit

/// SwiftUI -> UIKit presentation bridge.
///
/// SEASession.start(config:from:callbacks:) (api-contract-ios-v1.md §4) wants a
/// `UIViewController` to present from. Rather than wrapping the whole app in a
/// `UIViewControllerRepresentable` (which would fight the SwiftUI App lifecycle
/// for no benefit here), we resolve the current key-window's top-most presented
/// UIViewController on demand — the root of a SwiftUI `App` is already a
/// UIHostingController under the hood, so this is a legitimate, minimal seam.
enum TopViewControllerResolver {
    @MainActor
    static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.first as? UIWindowScene

        guard let windowScene else { return nil }

        let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        guard var top = window?.rootViewController else { return nil }

        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

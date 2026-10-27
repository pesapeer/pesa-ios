#if canImport(UIKit)
import SwiftUI
import UIKit

/// Keeps the card screen out of screenshots, screen recordings and the
/// app-switcher snapshot. iOS has no FLAG_SECURE; the established way is a
/// secure text field layered under the window's content, which makes the
/// system render the whole layer tree as blank in captures. On top of that
/// the window is covered while the app is inactive.
///
/// Apple does not document the layer trick; it is what every payments SDK
/// ships and it must be checked on a device after each major iOS release.
@MainActor
public final class SecureScreenGuard {
    public static let shared = SecureScreenGuard()

    private var secureField: UITextField?
    private var cover: UIView?
    private var observers: [NSObjectProtocol] = []
    private var holders = 0

    private init() {}

    private var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    }

    /// Reference counted: the guard stays on until every holder has released.
    public func acquire() {
        holders += 1
        guard secureField == nil, let window else { return }
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        window.addSubview(field)
        window.layer.superlayer?.addSublayer(field.layer)
        field.layer.sublayers?.last?.addSublayer(window.layer)
        secureField = field

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showCover() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hideCover() }
        })
    }

    public func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        hideCover()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let field = secureField, let window else { return }
        field.layer.sublayers?.last?.sublayers?.removeAll { $0 == window.layer }
        window.layer.superlayer?.addSublayer(window.layer)
        field.layer.removeFromSuperlayer()
        field.removeFromSuperview()
        secureField = nil
    }

    private func showCover() {
        guard cover == nil, let window else { return }
        let view = UIView(frame: window.bounds)
        view.backgroundColor = .systemBackground
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(view)
        cover = view
    }

    private func hideCover() {
        cover?.removeFromSuperview()
        cover = nil
    }
}

/// `.pesaSecureScreen()` on the view that shows the card form.
public struct PesaSecureScreen: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .onAppear { SecureScreenGuard.shared.acquire() }
            .onDisappear { SecureScreenGuard.shared.release() }
    }
}

public extension View {
    func pesaSecureScreen() -> some View { modifier(PesaSecureScreen()) }
}
#endif

import LinkKit
import UIKit

// Retained for the duration of the Link session
private var activeLinkHandler: Handler?

func openPlaidLink(
    token: String,
    onSuccess: @escaping (String, String, String) -> Void,
    onExit: @escaping () -> Void
) {
    var config = LinkTokenConfiguration(token: token) { (success: LinkSuccess) in
        activeLinkHandler = nil
        let institution = success.metadata.institution
        onSuccess(success.publicToken, institution.name, institution.id)
    }
    config.onExit = { (_: LinkExit) in
        activeLinkHandler = nil
        onExit()
    }

    guard case .success(let handler) = Plaid.create(config) else {
        onExit()
        return
    }

    activeLinkHandler = handler

    guard let topVC = UIApplication.shared.topPresentedViewController() else {
        onExit()
        return
    }

    let mode: PresentationMethod = .viewController(topVC)
    handler.open(presentUsing: mode)
}

private extension UIApplication {
    func topPresentedViewController() -> UIViewController? {
        let keyWindow = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

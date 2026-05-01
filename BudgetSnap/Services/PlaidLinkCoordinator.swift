import LinkKit
import SwiftUI

struct PlaidLinkView: UIViewControllerRepresentable {
    let linkToken: String
    let onSuccess: (String, String, String) -> Void  // (publicToken, institutionName, institutionId)
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        return vc
    }

    // Called after the VC is in the window hierarchy — safe to present from here
    func updateUIViewController(_ vc: UIViewController, context: Context) {
        guard context.coordinator.handler == nil else { return }

        var config = LinkTokenConfiguration(token: linkToken) { (success: LinkSuccess) in
            let institution = success.metadata.institution
            onSuccess(success.publicToken, institution.name, institution.id)
        }
        config.onExit = { (_: LinkExit) in onExit() }

        switch Plaid.create(config) {
        case .success(let handler):
            context.coordinator.handler = handler
            let mode: PresentationMethod = .viewController(vc)
            handler.open(presentUsing: mode)
        case .failure:
            onExit()
        }
    }

    final class Coordinator {
        var handler: Handler?
    }
}

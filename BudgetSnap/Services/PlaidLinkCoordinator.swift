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

        var config = LinkTokenConfiguration(token: linkToken) { success in
            let name = success.metadata.institution?.name ?? "Unknown"
            let id = success.metadata.institution?.id ?? ""
            onSuccess(success.publicToken, name, id)
        }
        config.onExit = { _ in onExit() }

        switch Plaid.create(config) {
        case .success(let handler):
            context.coordinator.handler = handler
            handler.open(presentUsing: .viewController(vc))
        case .failure:
            onExit()
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator {
        var handler: Handler?
    }
}

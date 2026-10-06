import UIKit

@main
@MainActor
final class ShareTestSender: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = FixtureViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

@MainActor
private final class FixtureViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        for filename in [
            "gbdk450-rev-v1.0.gb", "gbdk450-dual.gbc",
            "gbdk450-rev-v1.0-to-v1.1.ips", "gbdk450-rev-v1.0-to-v1.1.bps"
        ] {
            let button = UIButton(type: .system)
            button.setTitle(filename, for: .normal)
            button.accessibilityIdentifier = filename
            button.addAction(UIAction { [weak self] _ in self?.share(filename) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    private func share(_ filename: String) {
        let name = (filename as NSString).deletingPathExtension
        let suffix = (filename as NSString).pathExtension
        guard let resource = Bundle.main.url(forResource: name, withExtension: suffix) else {
            preconditionFailure("Missing shared-file fixture: \(filename)")
        }
        do {
            let url = URL.documentsDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            try FileManager.default.copyItem(at: resource, to: url)
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            present(sheet, animated: true)
        } catch {
            preconditionFailure("Could not prepare shared-file fixture: \(error)")
        }
    }
}

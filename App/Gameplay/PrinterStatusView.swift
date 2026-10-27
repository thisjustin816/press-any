import EmulationCore
import UIKit

@MainActor
final class PrinterStatusView: UIView {
    var onViewPrint: (() -> Void)?
    let spinner = UIActivityIndicatorView(style: .medium)
    let message = UILabel()
    let viewPrint = UIButton(type: .system)
    let dismissButton = UIButton(type: .system)
    private var hasReadyPrint = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 16
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)
        message.font = .preferredFont(forTextStyle: .subheadline)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 2
        var configuration = UIButton.Configuration.filled()
        configuration.title = "View Print"
        configuration.image = UIImage(systemName: "printer")
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        viewPrint.configuration = configuration
        viewPrint.accessibilityIdentifier = "printer.viewPrint"
        viewPrint.addAction(UIAction { [weak self] _ in self?.onViewPrint?() }, for: .touchUpInside)
        dismissButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        dismissButton.accessibilityLabel = "Dismiss print notification"
        dismissButton.addAction(UIAction { [weak self] _ in self?.dismissReadyPrint() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [spinner, message, viewPrint, dismissButton])
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            viewPrint.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            dismissButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            dismissButton.widthAnchor.constraint(equalToConstant: 44),
        ])
        showActivity(.idle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showActivity(_ activity: PrinterActivity) {
        guard activity != .idle else {
            if !hasReadyPrint { isHidden = true }
            return
        }
        hasReadyPrint = false
        isHidden = false
        message.text = activity == .receiving ? "Receiving print..." : "Printing..."
        viewPrint.isHidden = true
        dismissButton.isHidden = true
        spinner.isHidden = false
        spinner.startAnimating()
    }

    func showReadyPrint() {
        hasReadyPrint = true
        isHidden = false
        message.text = "Print ready"
        spinner.stopAnimating()
        spinner.isHidden = true
        viewPrint.isHidden = false
        dismissButton.isHidden = false
    }

    func dismissReadyPrint() {
        hasReadyPrint = false
        isHidden = true
    }
}

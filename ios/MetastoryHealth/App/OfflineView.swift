import UIKit

/// Shown only when the very first load fails — after that the service worker
/// has a cached copy and the page can speak for itself.
final class OfflineView: UIView {

    var message: String = "" {
        didSet { messageLabel.text = message }
    }

    private let messageLabel = UILabel()
    private let onRetry: () -> Void

    init(onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = UIColor(hex: AppConfig.backgroundColorHex)

        let title = UILabel()
        title.text = "Metastory Health"
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = UIColor(hex: 0x3A3A36)
        title.textAlignment = .center

        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = UIColor(hex: 0x6B6B63)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        var config = UIButton.Configuration.filled()
        config.title = "Try Again"
        config.baseBackgroundColor = UIColor(hex: 0x2F6F4E)
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28)

        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.onRetry()
        })

        let stack = UIStackView(arrangedSubviews: [title, messageLabel, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(24, after: messageLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32)
        ])
    }
}

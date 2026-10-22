import SwiftUI
import UIKit

/// iOS 17.4 has no SwiftUI scroll-geometry callback for Lists and Forms.
struct ScrollOverflowObserver: UIViewRepresentable {
    @Binding var hasMoreBelow: Bool

    func makeUIView(context: Context) -> ScrollOverflowProbe {
        ScrollOverflowProbe { hasMoreBelow = $0 }
    }

    func updateUIView(_ uiView: ScrollOverflowProbe, context: Context) {
        uiView.onChange = { hasMoreBelow = $0 }
        uiView.scheduleConnection()
    }

    static func dismantleUIView(_ uiView: ScrollOverflowProbe, coordinator: ()) {
        uiView.stopObserving()
    }
}

final class ScrollOverflowProbe: UIView {
    var onChange: (Bool) -> Void
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var connectionScheduled = false
    private var reportScheduled = false
    private var lastReported: Bool?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopObserving()
        } else {
            scheduleConnection()
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        scheduleConnection()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleConnection()
    }

    func scheduleConnection() {
        guard !connectionScheduled else { return }
        connectionScheduled = true
        // UIKit finishes constructing the scroll view after SwiftUI inserts its background.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.connectionScheduled = false
            self.connect()
        }
    }

    func stopObserving() {
        observations.removeAll()
        scrollView = nil
        lastReported = nil
    }

    private func connect() {
        guard window != nil else { return }
        guard let candidate = findScrollView() else {
            stopObserving()
            return
        }
        if candidate !== scrollView {
            stopObserving()
            scrollView = candidate
            observations = [
                candidate.observe(\.contentOffset) { [weak self] _, _ in
                    Task { @MainActor in self?.scheduleReport() }
                },
                candidate.observe(\.contentSize) { [weak self] _, _ in
                    Task { @MainActor in self?.scheduleReport() }
                },
                candidate.observe(\.bounds) { [weak self] _, _ in
                    Task { @MainActor in self?.scheduleReport() }
                },
                candidate.observe(\.adjustedContentInset) { [weak self] _, _ in
                    Task { @MainActor in self?.scheduleReport() }
                },
                candidate.observe(\.contentInset) { [weak self] _, _ in
                    Task { @MainActor in self?.scheduleReport() }
                },
            ]
        }
        scheduleReport()
    }

    private func scheduleReport() {
        guard !reportScheduled else { return }
        reportScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reportScheduled = false
            guard let scrollView = self.scrollView, self.window != nil else { return }
            let more = ScrollOverflow.hasMoreBelow(
                contentHeight: scrollView.contentSize.height,
                viewportHeight: scrollView.bounds.height,
                offsetY: scrollView.contentOffset.y,
                topInset: scrollView.adjustedContentInset.top,
                bottomInset: scrollView.adjustedContentInset.bottom
            )
            guard more != self.lastReported else { return }
            self.lastReported = more
            self.onChange(more)
        }
    }

    private func findScrollView() -> UIScrollView? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        var ancestor = superview
        while let view = ancestor, !(view is UIWindow) {
            if let scrollView = scrollView(in: view) { return scrollView }
            ancestor = view.superview
        }
        return nil
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        guard view !== self else { return nil }
        if let scrollView = view as? UIScrollView {
            let viewport = scrollView.convert(scrollView.bounds, to: self)
            let overlap = viewport.intersection(bounds)
            return overlap.width >= bounds.width * 0.8 && overlap.height >= bounds.height * 0.8
                ? scrollView : nil
        }
        for child in view.subviews {
            if let scrollView = scrollView(in: child) { return scrollView }
        }
        return nil
    }
}

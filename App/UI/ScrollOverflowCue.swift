import SwiftUI

extension View {
    func scrollOverflowCue() -> some View {
        modifier(ScrollOverflowCue())
    }
}

private struct ScrollOverflowCue: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hasMoreBelow = false

    func body(content: Content) -> some View {
        observed(content)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    if hasMoreBelow && !reduceTransparency {
                        LinearGradient(
                            colors: [.black, .black.opacity(0.15)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 48)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if hasMoreBelow {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if reduceTransparency {
                                Capsule().fill(Color(uiColor: .secondarySystemBackground))
                            } else {
                                Capsule().fill(.regularMaterial)
                            }
                        }
                        .padding(.bottom, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder
    private func observed(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                ScrollOverflow.hasMoreBelow(
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.containerSize.height,
                    offsetY: geometry.contentOffset.y,
                    topInset: geometry.contentInsets.top,
                    bottomInset: geometry.contentInsets.bottom
                )
            } action: { _, more in
                hasMoreBelow = more
            }
        } else {
            content.background {
                ScrollOverflowObserver(hasMoreBelow: $hasMoreBelow)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

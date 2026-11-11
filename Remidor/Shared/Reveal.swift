//
//  Reveal.swift
//  Remidor
//
//  Created by n9ine on 08.11.2026.
//

import SwiftUI

/// The pace of things opening and closing in the boxes. One value, so the content, the window and the rows around
/// it all move together.
enum Motion {
    static let reveal = Animation.smooth(duration: 0.28)
}

/// Makes room for its content bit by bit, from the top, instead of the content appearing at full size and
/// the rows around it sliding over it.
private struct RevealLayout: Layout {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        view.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}

/// A view that opens up and fades in. Its height grows from nothing, so what is around it is pushed aside
/// smoothly and never overlapped. Only for coming in: a view that is taken out gives up its room at once, so
/// closing is done by `Reveal`, which keeps it there while it shrinks.
struct RevealTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        RevealLayout(progress: phase.isIdentity ? 1 : 0) {
            content.opacity(phase.isIdentity ? 1 : 0)
        }
        .clipped()
    }
}

extension AnyTransition {
    /// Opens up like `RevealTransition` and, when taken out, is simply gone, rather than fading over the rows that
    /// have already moved up into its place.
    static var reveal: AnyTransition {
        .asymmetric(insertion: AnyTransition(RevealTransition()), removal: .identity)
    }
}

/// Shows its content by opening up and hides it by closing again, keeping the content in place while it shrinks so
/// the rows around it follow it smoothly both ways.
struct Reveal<Content: View>: View {
    let shown: Bool
    @ViewBuilder let content: () -> Content

    @State private var mounted: Bool
    @State private var progress: CGFloat

    init(shown: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.shown = shown
        self.content = content
        _mounted = State(initialValue: shown)
        _progress = State(initialValue: shown ? 1 : 0)
    }

    var body: some View {
        Group {
            if mounted {
                RevealLayout(progress: progress) {
                    content().opacity(progress)
                }
                .clipped()
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
            }
        }
        .onChange(of: shown) { _, now in
            if now {
                mounted = true
                withAnimation(Motion.reveal) { progress = 1 }
            } else {
                withAnimation(Motion.reveal) {
                    progress = 0
                } completion: {
                    if !shown { mounted = false }
                }
            }
        }
    }
}

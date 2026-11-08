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

/// A view that opens up and fades in, and closes the same way. Its height grows from nothing, so what is
/// around it is pushed aside smoothly and never overlapped.
struct RevealTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        RevealLayout(progress: phase.isIdentity ? 1 : 0) {
            content.opacity(phase.isIdentity ? 1 : 0)
        }
        .clipped()
    }
}

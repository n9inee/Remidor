//
//  NotesEditor.swift
//  Remidor
//
//  Created by n9ine on 10.11.2026.
//

import AppKit
import SwiftUI

/// A plain-text box for notes that carries a bullet list on when Return is pressed (see `NotesFormatting`).
/// It wraps `NSTextView` because SwiftUI's `TextEditor` can't see the caret or catch Return.
struct NotesEditor: NSViewRepresentable {
    @Binding var text: String
    let onCancel: () -> Void
    /// The box lost the keyboard focus, for instance because something else in the panel was clicked.
    var onEnd: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 13)
        view.textContainerInset = NSSize(width: 2, height: 4)
        // Typing "- " or "--" must stay exactly that, since it is saved as typed.
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.string = text
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let view = scroll.documentView as? NSTextView, view.string != text { view.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesEditor

        init(_ parent: NotesEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEnd()
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let selection = view.selectedRange()
                guard selection.length == 0,
                      let edit = NotesFormatting.returnEdit(in: view.string, caret: selection.location) else { return false }
                view.insertText(edit.replacement, replacementRange: edit.range)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

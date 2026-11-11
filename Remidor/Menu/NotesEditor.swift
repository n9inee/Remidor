//
//  NotesEditor.swift
//  Remidor
//
//  Created by n9ine on 10.11.2026.
//

import AppKit
import SwiftUI

/// A plain-text box for notes. Return saves, and Shift + Return starts a new line, which carries a bullet list on
/// (see `NotesFormatting`).
/// It wraps `NSTextView` because SwiftUI's `TextEditor` can't see the caret or catch Return.
struct NotesEditor: NSViewRepresentable {
    @Binding var text: String
    /// Esc. Without one, Esc is left for whatever holds the box, such as the panel closing.
    var onCancel: (() -> Void)?
    /// The box lost the keyboard focus, for instance because something else in the panel was clicked.
    var onEnd: () -> Void = {}
    /// Return. Without one, Return starts a new line like any text box.
    var onSubmit: (() -> Void)?
    /// Takes the keyboard as soon as it is shown. Off for a box that sits under another one with the focus.
    var focusesOnAppear = true

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
        if focusesOnAppear {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            }
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

        /// A new line that carries a bullet list on. False on a line that isn't a bullet.
        private func newLine(in view: NSTextView) -> Bool {
            let selection = view.selectedRange()
            guard selection.length == 0,
                  let edit = NotesFormatting.returnEdit(in: view.string, caret: selection.location) else { return false }
            view.insertText(edit.replacement, replacementRange: edit.range)
            return true
        }

        private func insertPlainNewLine(in view: NSTextView) -> Bool {
            view.insertText("\n", replacementRange: view.selectedRange())
            return true
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                if !shift, let submit = parent.onSubmit {
                    submit()
                    return true
                }
                return newLine(in: view) || (parent.onSubmit != nil && insertPlainNewLine(in: view))
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return newLine(in: view) || insertPlainNewLine(in: view)
            case #selector(NSResponder.cancelOperation(_:)):
                guard let cancel = parent.onCancel else { return false }
                cancel()
                return true
            default:
                return false
            }
        }
    }
}

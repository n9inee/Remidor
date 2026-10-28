//
//  HighlightedTextField.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import AppKit
import SwiftUI

/// A single-line text field that colors recognized quick-add tokens as you type. SwiftUI's
/// `TextField` can't style parts of its text, so this wraps an `NSTextField`.
struct HighlightedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var tokens: [QuickAddParser.Token]
    var color: (QuickAddParser.Token) -> NSColor
    /// Changing this value moves keyboard focus into the field.
    var focusTrigger: Int
    var onSubmit: () -> Void
    /// Shift + Return.
    var onShiftSubmit: () -> Void = {}
    /// Return true to keep Tab inside the field; false lets it move focus to the next control.
    var onTab: () -> Bool
    var onMove: (Int) -> Bool = { _ in false }
    /// Selects the whole text when focus arrives, as when renaming; otherwise the cursor goes to the end.
    var selectsAllOnFocus = false

    private static let font = NSFont.systemFont(ofSize: 13)

    /// A field that takes focus as soon as it is in a window, for one asked to focus while it was still being built.
    final class FocusingField: NSTextField {
        var focusWhenAttached = false
        var selectsAll = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard focusWhenAttached, window != nil else { return }
            focusWhenAttached = false
            // The window is still settling when it gets here, so ask once it has.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
                let length = (self.stringValue as NSString).length
                (self.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: self.selectsAll ? 0 : length, length: self.selectsAll ? length : 0))
            }
        }
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusingField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Self.font
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        let end = NSRange(location: (text as NSString).length, length: 0)

        if field.stringValue != text {
            field.stringValue = text
            (field.currentEditor() as? NSTextView)?.setSelectedRange(end)
        }
        highlight(field)

        if focusTrigger != context.coordinator.lastFocus {
            context.coordinator.lastFocus = focusTrigger
            (field as? FocusingField)?.selectsAll = selectsAllOnFocus
            if field.window == nil {
                (field as? FocusingField)?.focusWhenAttached = true
            } else {
                field.window?.makeFirstResponder(field)
                let all = NSRange(location: 0, length: end.location)
                (field.currentEditor() as? NSTextView)?.setSelectedRange(selectsAllOnFocus ? all : end)
            }
        }
    }

    /// Colors the tokens, either in the live editor (keeping the cursor) or in the idle field.
    private func highlight(_ field: NSTextField) {
        let base: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.labelColor]

        func paint(_ string: NSMutableAttributedString) {
            string.setAttributes(base, range: NSRange(location: 0, length: string.length))
            for token in tokens where NSMaxRange(token.range) <= string.length {
                let tint = color(token)
                string.addAttributes([.foregroundColor: tint, .backgroundColor: tint.withAlphaComponent(0.16)], range: token.range)
            }
        }

        if let editor = field.currentEditor() as? NSTextView, let storage = editor.textStorage {
            storage.beginEditing()
            paint(storage)
            storage.endEditing()
            editor.typingAttributes = base
        } else {
            let string = NSMutableAttributedString(string: text)
            paint(string)
            field.attributedStringValue = string
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HighlightedTextField
        var lastFocus = 0

        init(_ parent: HighlightedTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { parent.onShiftSubmit() } else { parent.onSubmit() }
                return true
            case #selector(NSResponder.insertLineBreak(_:)): parent.onShiftSubmit(); return true
            case #selector(NSResponder.insertTab(_:)): return parent.onTab()
            case #selector(NSResponder.moveUp(_:)): return parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): return parent.onMove(1)
            default: return false
            }
        }
    }
}

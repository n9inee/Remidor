//
//  NotesFormatting.swift
//  Remidor
//
//  Created by n9ine on 10.11.2026.
//

import Foundation

/// Bullet lists in notes. Reminders keeps notes as plain text, so a list is just lines that start with `* `
/// or `- `. What is saved is always exactly what was typed. Only the way it is shown and typed in changes.
enum NotesFormatting {
    /// A change to make to the text: put `replacement` where `range` is.
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
    }

    /// What Return should do with the caret at `caret` (a UTF-16 offset). On a bullet line it carries the list on
    /// with the next bullet, and on an empty bullet it ends the list. Nil on any other line: Return is left alone.
    static func returnEdit(in text: String, caret: Int) -> Edit? {
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let before = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        guard let bullet = bullet(in: before) else { return nil }
        if bullet.rest.trimmingCharacters(in: .whitespaces).isEmpty {
            return Edit(range: NSRange(location: lineStart, length: caret - lineStart), replacement: "")
        }
        return Edit(range: NSRange(location: caret, length: 0), replacement: "\n" + bullet.indent + bullet.marker + " ")
    }

    /// The notes as shown when not being edited: `* ` and `- ` bullets drawn as `• `.
    static func displayed(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?m)^([ \t]*)[*-] "#, with: "$1• ", options: .regularExpression)
    }

    /// The notes as shown in a task's details: runs of empty lines shrink to one, and anything past `limit` lines is
    /// cut with an ellipsis. Editing the notes shows them in full.
    static func detail(_ notes: String, limit: Int = 6) -> String {
        var lines: [String] = []
        for raw in displayed(notes).components(separatedBy: .newlines) {
            let line = String(raw.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
            if line.isEmpty {
                if lines.last?.isEmpty == false { lines.append("") }
            } else {
                lines.append(line)
            }
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        guard lines.count > limit else { return lines.joined(separator: "\n") }
        return lines.prefix(limit).joined(separator: "\n") + "…"
    }

    /// The first lines of the notes that have anything in them, bullets drawn as `• `, for showing under a title.
    static func previewLines(_ notes: String?, limit: Int = 2) -> [String] {
        guard let notes else { return [] }
        let lines = displayed(notes).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(limit))
    }

    /// The indent, bullet character and what follows it, if the line starts with a bullet.
    private static func bullet(in line: String) -> (indent: String, marker: String, rest: String)? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let tail = line.dropFirst(indent.count)
        guard let first = tail.first, "*-•".contains(first), tail.dropFirst().first == " " else { return nil }
        return (indent, String(first), String(tail.dropFirst(2)))
    }
}

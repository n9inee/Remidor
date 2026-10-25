//
//  RemidorTests.swift
//  RemidorTests
//
//  Created by n9ine on 23.10.2026.
//

import Foundation
import SwiftUI
import Testing
@testable import Remidor

@MainActor
struct QuickAddParserTests {
    private let lists = ["Inbox", "Work", "My List"]

    private func hour(_ date: Date?) -> Int? { date.map { Calendar.current.component(.hour, from: $0) } }

    @Test func plainTitleIsUntouched() {
        let result = QuickAddParser.parse("buy 2 apples", listNames: lists)
        #expect(result.title == "buy 2 apples")
        #expect(result.due == nil)
        #expect(result.priority == nil)
        #expect(result.tokens.isEmpty)
    }

    @Test func priorityMarks() {
        #expect(QuickAddParser.parse("call mom !!!", listNames: lists).priority == 1)
        #expect(QuickAddParser.parse("call mom !!", listNames: lists).priority == 5)
        #expect(QuickAddParser.parse("call mom !", listNames: lists).priority == 9)
        #expect(QuickAddParser.parse("call mom !!!", listNames: lists).title == "call mom")
    }

    @Test func listByNameOrPrefix() {
        #expect(QuickAddParser.parse("pay rent ~work", listNames: lists).listName == "Work")
        #expect(QuickAddParser.parse("pay rent ~inb", listNames: lists).listName == "Inbox")
        #expect(QuickAddParser.parse(#"pay rent ~"My List""#, listNames: lists).listName == "My List")
    }

    @Test func unknownListStaysInTheTitle() {
        let result = QuickAddParser.parse("pay rent ~nowhere", listNames: lists)
        #expect(result.listName == nil)
        #expect(result.title == "pay rent ~nowhere")
    }

    @Test func tagsAreHighlightedButKept() {
        let result = QuickAddParser.parse("send invoice #acme", listNames: lists)
        #expect(result.title == "send invoice #acme")
        #expect(result.tokens.contains { $0.kind == .tag })
    }

    @Test func shorthandDates() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        for phrase in ["tmr", "tmrw", "2moro"] {
            let result = QuickAddParser.parse("water plants \(phrase)", listNames: lists)
            #expect(result.title == "water plants")
            #expect(result.due.map { Calendar.current.isDate($0, inSameDayAs: tomorrow) } == true, "\(phrase)")
            #expect(!result.hasTime)
        }
    }

    @Test func bareHoursGuessTheTimeOfDay() {
        #expect(hour(QuickAddParser.parse("call tmrw at 8", listNames: lists).due) == 8)
        #expect(hour(QuickAddParser.parse("call tmrw at 4", listNames: lists).due) == 16)
        #expect(hour(QuickAddParser.parse("call tmrw at 12", listNames: lists).due) == 12)
        #expect(hour(QuickAddParser.parse("call tmrw at 8pm", listNames: lists).due) == 20)
        #expect(QuickAddParser.parse("call tmrw at 8", listNames: lists).hasTime)
    }

    @Test func relativeDates() {
        let result = QuickAddParser.parse("stretch in 20 mins", listNames: lists)
        #expect(result.title == "stretch")
        #expect(result.hasTime)
        let minutes = result.due.map { $0.timeIntervalSinceNow / 60 } ?? 0
        #expect((19...21).contains(minutes))
    }

    @Test func everythingTogether() {
        let result = QuickAddParser.parse("call mom tmrw at 8pm !!! * ~Inbox #phone", listNames: lists)
        #expect(result.title == "call mom #phone")
        #expect(result.priority == 1)
        #expect(result.flagged)
        #expect(result.listName == "Inbox")
        #expect(result.hasTime)
        #expect(Set(result.tokens.map(\.kind)) == [.date, .priority, .flag, .list, .tag])
    }

    @Test func emptyAndBlankInput() {
        for input in ["", "   ", "\n"] {
            let result = QuickAddParser.parse(input, listNames: lists)
            #expect(result.title.isEmpty)
            #expect(result.tokens.isEmpty)
            #expect(result.due == nil)
        }
    }

    @Test func lonelyMarkersAreJustText() {
        #expect(QuickAddParser.parse("~", listNames: lists).title == "~")
        #expect(QuickAddParser.parse("#", listNames: lists).title == "#")
        #expect(QuickAddParser.parse("hello!", listNames: lists).priority == nil)
        #expect(QuickAddParser.parse("wow!!!", listNames: lists).priority == nil)
    }

    @Test func onlyTheFirstListIsUsed() {
        let result = QuickAddParser.parse("x ~Work ~Inbox", listNames: lists)
        #expect(result.listName == "Work")
        #expect(result.title == "x ~Inbox")
    }

    @Test func tokenRangesSurviveEmoji() {
        let input = "🙂 call mom tmrw !!!"
        let result = QuickAddParser.parse(input, listNames: lists)
        let ns = input as NSString
        let pieces = Set(result.tokens.map { ns.substring(with: $0.range) })
        #expect(pieces == ["tmrw", "!!!"])
        #expect(result.title == "🙂 call mom")
    }

    @Test func starFlagsTheReminder() {
        let result = QuickAddParser.parse("buy milk *", listNames: lists)
        #expect(result.flagged)
        #expect(result.title == "buy milk")
        #expect(result.tokens.map(\.kind) == [.flag])
        #expect(QuickAddParser.parse("* call mom tmrw", listNames: lists).flagged)
    }

    @Test func starsInsideWordsDoNotFlag() {
        for input in ["wow*", "*bold*", "5*3", "**", "a *b"] {
            #expect(!QuickAddParser.parse(input, listNames: lists).flagged, "\(input)")
        }
        #expect(QuickAddParser.parse("*bold*", listNames: lists).title == "*bold*")
    }

    @Test func autocompleteToken() {
        #expect(QuickAddParser.activeToken(in: "call mom ~Wo")?.query == "Wo")
        #expect(QuickAddParser.activeToken(in: "call mom #ph")?.trigger == "#")
        #expect(QuickAddParser.activeToken(in: "call mom") == nil)
        #expect(QuickAddParser.activeToken(in: "call mom *")?.trigger == "*")
    }
}

@MainActor
struct OrderingTests {
    private func item(_ id: String, _ title: String, due: Date? = nil, priority: Int = 0, parent: String? = nil) -> ReminderItem {
        ReminderItem(id: id, title: title, listID: "list", listTitle: "List", listColor: .blue,
                     due: due, priority: priority, parentID: parent)
    }

    @Test func dueTimeThenPriorityThenTitle() {
        let nine = Date(timeIntervalSince1970: 1_000_000)
        let ten = nine.addingTimeInterval(3600)
        let items = [
            item("1", "B", due: ten, priority: 1),
            item("2", "C", due: nine),
            item("3", "A", due: nine),
            item("4", "D", due: nine, priority: 1),
        ]
        #expect(items.sortedByDueTime().map(\.id) == ["4", "3", "2", "1"])
    }

    @Test func priorityOrderPutsUnprioritisedLast() {
        let items = [item("1", "A"), item("2", "B", priority: 9), item("3", "C", priority: 1)]
        #expect(items.sorted(by: .priority).map(\.id) == ["3", "2", "1"])
    }

    @Test func subtasksSitUnderTheirParent() {
        let items = [
            item("c", "Child", parent: "p"),
            item("p", "Parent"),
            item("x", "Other"),
        ]
        let nested = items.nestingSubtasks()
        #expect(nested.map(\.id) == ["p", "c", "x"])
        #expect(nested.map(\.depth) == [0, 1, 0])
    }

    @Test func subtasksPointingAtEachOtherAreNotDropped() {
        let items = [item("a", "A", parent: "b"), item("b", "B", parent: "a"), item("c", "C")]
        let nested = items.nestingSubtasks()
        #expect(Set(nested.map(\.id)) == ["a", "b", "c"])
        #expect(nested.count == 3)
    }

    @Test func subtaskWithoutParentHereStaysTopLevel() {
        let nested = [item("c", "Child", parent: "missing")].nestingSubtasks()
        #expect(nested.map(\.depth) == [0])
    }
}

@MainActor
struct SmartListTests {
    @Test func flaggedListHasItsOwnIcon() {
        #expect(SmartList.flagged.symbol == "flag.fill")
        #expect(SmartList.today.symbol == "sparkles")
        #expect(ReminderList(id: "x", title: "X", color: .blue).symbol == "list.bullet")
    }

    @Test func smartListsComeInTheUsualOrder() {
        #expect(SmartList.allLists.map(\.title) == ["Today", "Scheduled", "Flagged", "All"])
    }

    @Test func flaggedAndAllSortByTheUsersChoiceNotByTime() {
        #expect(SmartList.sortsByTime(SmartList.today))
        #expect(SmartList.sortsByTime(SmartList.scheduled))
        #expect(!SmartList.sortsByTime(SmartList.flagged))
        #expect(!SmartList.sortsByTime(SmartList.all))
    }
}

@MainActor
struct FormattingTests {
    @Test func countdown() {
        #expect(formatRemaining(65) == "1:05")
        #expect(formatRemaining(3725) == "1:02:05")
        #expect(formatRemaining(0) == "0:00")
    }

    @Test func dateOnlyReminderShowsNoTime() {
        let today = Calendar.current.startOfDay(for: Date())
        #expect(describeDue(today, hasTime: false) == "Today")
        #expect(describeDue(today, hasTime: true).hasPrefix("Today, "))
    }
}

@MainActor
struct UpdateCheckerTests {
    @Test func versionsCompareNumberByNumber() {
        #expect(UpdateChecker.isNewer("1.1.0", than: "1.0.0"))
        #expect(UpdateChecker.isNewer("1.10", than: "1.9"))
        #expect(UpdateChecker.isNewer("2", than: "1.9.9"))
        #expect(UpdateChecker.isNewer("v1.2.0", than: "1.1.9"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        #expect(!UpdateChecker.isNewer("1.0", than: "1.1"))
        #expect(!UpdateChecker.isNewer("garbage", than: "1.0"))
    }

    @Test func suffixIsIgnored() {
        #expect(!UpdateChecker.isNewer("1.1.0-beta1", than: "1.1.0"))
        #expect(UpdateChecker.isNewer("1.2.0-beta1", than: "1.1.0"))
    }

    private func json(tag: String, url: String, draft: Bool = false, prerelease: Bool = false) -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)","draft":\#(draft),"prerelease":\#(prerelease),"extra":1}"#.utf8)
    }

    @Test func readsAReleaseFromThisRepository() {
        let url = "https://github.com/\(UpdateChecker.repository)/releases/tag/v1.2.0"
        let update = UpdateChecker.parse(json(tag: "v1.2.0", url: url))
        #expect(update?.version == "1.2.0")
        #expect(update?.url.absoluteString == url)
    }

    @Test func ignoresDraftsAndPrereleases() {
        let url = "https://github.com/\(UpdateChecker.repository)/releases/tag/v1.2.0"
        #expect(UpdateChecker.parse(json(tag: "v1.2.0", url: url, draft: true)) == nil)
        #expect(UpdateChecker.parse(json(tag: "v1.2.0", url: url, prerelease: true)) == nil)
    }

    @Test func refusesLinksToOtherPlaces() {
        #expect(UpdateChecker.parse(json(tag: "v9.0", url: "https://evil.example.com/download")) == nil)
        #expect(UpdateChecker.parse(json(tag: "v9.0", url: "https://github.com/someone-else/Remidor/releases/tag/v9.0")) == nil)
        #expect(UpdateChecker.parse(json(tag: "v9.0", url: "http://github.com/\(UpdateChecker.repository)/releases")) == nil)
    }

    @Test func survivesGarbage() {
        #expect(UpdateChecker.parse(Data()) == nil)
        #expect(UpdateChecker.parse(Data("not json".utf8)) == nil)
        #expect(UpdateChecker.parse(Data(#"{"message":"Not Found"}"#.utf8)) == nil)
    }
}

@Suite struct ReminderEditingTests {
    private func day(_ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 9, minute: 30))!
    }

    @Test func movingKeepsTheTimeOfDay() {
        let moved = ReminderEditing.moving(day(3), hasTime: true, toDay: day(10))
        let parts = Calendar.current.dateComponents([.day, .hour, .minute], from: moved.date)
        #expect(moved.hasTime && parts.day == 10 && parts.hour == 9 && parts.minute == 30)
    }

    @Test func movingADateWithoutATimeStaysWithoutOne() {
        let moved = ReminderEditing.moving(nil, hasTime: false, toDay: day(10))
        #expect(!moved.hasTime && Calendar.current.component(.hour, from: moved.date) == 0)
    }
}

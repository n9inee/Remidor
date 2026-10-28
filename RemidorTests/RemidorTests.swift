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

    @Test func longerRelativeDates() throws {
        let calendar = Calendar.current
        func days(_ text: String) -> Int? {
            let result = QuickAddParser.parse(text, listNames: lists)
            return result.due.flatMap {
                calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: $0)).day
            }
        }
        #expect(days("pay in two weeks") == 14)
        #expect(days("pay in 3 days") == 3)
        #expect(days("pay in a week") == 7)
        #expect(QuickAddParser.parse("pay in two weeks", listNames: lists).title == "pay")
        let month = try #require(QuickAddParser.parse("renew in a month", listNames: lists).due)
        #expect(calendar.dateComponents([.month], from: Date(), to: month).month ?? 0 >= 0)
        #expect(!QuickAddParser.parse("renew in a month", listNames: lists).hasTime)
        let half = QuickAddParser.parse("tea in half an hour", listNames: lists)
        #expect(half.title == "tea")
        #expect(half.hasTime)
        #expect((29...31).contains(half.due.map { $0.timeIntervalSinceNow / 60 } ?? 0))
        #expect(QuickAddParser.parse("in a bit", listNames: lists).due == nil)
    }

    @Test func endOfMonthAndYear() throws {
        let calendar = Calendar.current
        let month = QuickAddParser.parse("rent end of the month", listNames: lists)
        #expect(month.title == "rent")
        let due = try #require(month.due)
        #expect(calendar.component(.month, from: due) == calendar.component(.month, from: Date()))
        #expect(calendar.component(.month, from: due.addingTimeInterval(86_400)) != calendar.component(.month, from: Date()))
        #expect(!month.hasTime)
        let year = try #require(QuickAddParser.parse("taxes eoy", listNames: lists).due)
        #expect(calendar.component(.month, from: year) == 12 && calendar.component(.day, from: year) == 31)
        #expect(QuickAddParser.parse("the end of days", listNames: lists).due == nil)
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

    private func placed(_ id: String, manual: Int = .max, section: Int = -1, parent: String? = nil) -> ReminderItem {
        var item = item(id, id, parent: parent)
        item.manualIndex = manual
        item.sectionIndex = section
        item.sectionTitle = section < 0 ? nil : "Section \(section)"
        item.sectionID = section < 0 ? nil : "s\(section)"
        return item
    }

    @Test func manualOrderFollowsTheListArrangement() {
        let items = [placed("c", manual: 2), placed("a", manual: 0), placed("z"), placed("b", manual: 1)]
        #expect(items.sorted(by: .manual).map(\.id) == ["a", "b", "c", "z"])
    }

    @Test func sectionsGroupItemsAndKeepTheirOrder() {
        let items = [placed("a", section: 1), placed("b"), placed("c", section: 0), placed("d", section: 1), placed("e")]
        #expect(items.groupedBySection().map(\.id) == ["c", "a", "d", "b", "e"])
    }

    @Test func subtasksJoinTheirParentsSection() {
        let items = [placed("p", section: 2), placed("k", section: 0, parent: "p")]
        let nested = items.nestingSubtasks()
        #expect(nested.map(\.id) == ["p", "k"])
        #expect(nested[1].sectionIndex == 2 && nested[0].childCount == 1)
    }

    @Test func foldedParentsHideTheirSubtasks() {
        let nested = [placed("p"), placed("k", parent: "p"), placed("q"), placed("m", parent: "q")].nestingSubtasks()
        #expect(nested.hidingFoldedSubtasks(["p"]).map(\.id) == ["p", "q", "m"])
        #expect(nested.hidingFoldedSubtasks([]).count == 4)
    }

    @Test func entriesShowEmptySectionsAndFoldedOnesAsHeadings() {
        let food = ReminderKit.ListSection(id: "f", title: "Food", index: 0)
        let empty = ReminderKit.ListSection(id: "e", title: "Empty", index: 1)
        let home = ReminderKit.ListSection(id: "h", title: "Home", index: 2)
        let list = ReminderList(id: "l", title: "L", color: .blue)
        let items = [placed("loose"), placed("a", section: 0), placed("b", section: 0), placed("c", section: 2)]
        var withIDs = items
        withIDs[1].sectionID = "f"; withIDs[2].sectionID = "f"; withIDs[3].sectionID = "h"
        let section = ReminderSection(list: list, items: withIDs, sections: [food, empty, home])

        let all = section.entries(foldedParents: [], foldedSections: [])
        #expect(all.map(\.id) == ["section:f", "a", "b", "section:e", "section:h", "c", "section:none", "loose"])
        let folded = section.entries(foldedParents: [], foldedSections: ["f"])
        #expect(folded.map(\.id) == ["section:f", "section:e", "section:h", "c", "section:none", "loose"])
        // Smart lists never show sections.
        let smart = ReminderSection(list: SmartList.today, items: withIDs, sections: [food])
        #expect(smart.entries(foldedParents: [], foldedSections: []).count == 4)
    }

    @Test func subtasksCanHaveAnOrderOfTheirOwn() {
        var late = placed("late", parent: "p"), early = placed("early", parent: "p")
        late.title = "b late"; early.title = "a early"
        late.manualIndex = 1; early.manualIndex = 2
        let items = [placed("p"), late, early]
        // Following the list, which here is the incoming order.
        #expect(items.nestingSubtasks().map(\.id) == ["p", "late", "early"])
        // A manual order for this parent puts the sub-tasks by their place.
        #expect(items.nestingSubtasks(childOrder: { _ in .manual }).map(\.id) == ["p", "late", "early"])
        // By title for this parent only.
        #expect(items.nestingSubtasks(childOrder: { $0 == "p" ? .title : nil }).map(\.id) == ["p", "early", "late"])
        #expect(items.nestingSubtasks(childOrder: { $0 == "other" ? .title : nil }).map(\.id) == ["p", "late", "early"])
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
        #expect(SmartList.allLists.map(\.title) == ["Today", "Next Up", "Scheduled", "Flagged", "All"])
    }

    @Test func flaggedAndAllSortByTheUsersChoiceNotByTime() {
        #expect(SmartList.sortsByTime(SmartList.today))
        #expect(SmartList.sortsByTime(SmartList.scheduled))
        #expect(SmartList.sortsByTime(SmartList.nextUp))
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

@MainActor
struct RecurrenceParsingTests {
    private func parse(_ text: String) -> QuickAddParser.Result {
        QuickAddParser.parse(text, listNames: ["Inbox"])
    }

    @Test func everyWeekdayNameRepeatsWeeklyFromTheNextOne() throws {
        let result = parse("Water plants every sunday")
        #expect(result.title == "Water plants")
        #expect(result.recurrence == Recurrence(frequency: .weekly, weekdays: [1]))
        let due = try #require(result.due)
        #expect(Calendar.current.component(.weekday, from: due) == 1)
        #expect(!result.hasTime)
        #expect(result.tokens.contains { $0.kind == .recurrence })
    }

    @Test func evAndOtherShortFormsWork() {
        #expect(parse("stretch ev day").recurrence == Recurrence(frequency: .daily))
        #expect(parse("stretch evry week").recurrence == Recurrence(frequency: .weekly))
        #expect(parse("rent every month").recurrence == Recurrence(frequency: .monthly))
        #expect(parse("Taxes every year").recurrence == Recurrence(frequency: .yearly))
    }

    @Test func intervalsAndSeveralDays() {
        #expect(parse("every 2 weeks").recurrence == Recurrence(frequency: .weekly, interval: 2))
        #expect(parse("every other day").recurrence == Recurrence(frequency: .daily, interval: 2))
        #expect(parse("laundry every other tuesday").recurrence == Recurrence(frequency: .weekly, interval: 2, weekdays: [3]))
        #expect(parse("sync every other mon and thu").recurrence == Recurrence(frequency: .weekly, interval: 2, weekdays: [2, 5]))
        #expect(parse("gym every mon and thu").recurrence == Recurrence(frequency: .weekly, weekdays: [2, 5]))
        #expect(parse("standup every weekday").recurrence == .weekdaysOnly)
    }

    @Test func aTimeStaysWithTheRepeat() throws {
        let result = parse("run every tue at 7am")
        let due = try #require(result.due)
        #expect(result.hasTime)
        #expect(Calendar.current.component(.weekday, from: due) == 3)
        #expect(Calendar.current.component(.hour, from: due) == 7)
        #expect(result.title == "run")
    }

    @Test func ordinaryWordsAreLeftAlone() {
        let result = parse("Charge ev charger")
        #expect(result.recurrence == nil)
        #expect(result.title == "Charge ev charger")
        #expect(parse("every").recurrence == nil)
    }

    @Test func labelsReadNaturally() {
        #expect(Recurrence(frequency: .daily).label == "Daily")
        #expect(Recurrence(frequency: .weekly, weekdays: [1]).label == "Every Sun")
        #expect(Recurrence.weekdaysOnly.label == "Weekdays")
        #expect(Recurrence(frequency: .weekly, interval: 2).label == "Every 2 weeks")
    }
}

@MainActor
struct OverdueTests {
    private func at(_ hour: Int, daysFromToday offset: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    @Test func aTimeStillAheadIsKept() {
        let now = at(9)
        let moved = ReminderEditing.rescheduling(at(15, daysFromToday: -2), hasTime: true, toDay: now, now: now)
        #expect(moved.hasTime)
        #expect(moved.date == at(15))
    }

    @Test func aTimeAlreadyGoneByLosesItsTime() {
        let now = at(15)
        let moved = ReminderEditing.rescheduling(at(9, daysFromToday: -1), hasTime: true, toDay: now, now: now)
        #expect(!moved.hasTime)
        #expect(moved.date == at(0))
    }

    @Test func aDateOnlyReminderJustGetsTheDay() {
        let moved = ReminderEditing.rescheduling(at(0, daysFromToday: -3), hasTime: false, toDay: at(12), now: at(12))
        #expect(!moved.hasTime)
        #expect(moved.date == at(0))
    }

    @Test func tomorrowAlwaysKeepsTheTime() {
        let now = at(15)
        let moved = ReminderEditing.rescheduling(at(9, daysFromToday: -1), hasTime: true, toDay: at(12, daysFromToday: 1), now: now)
        #expect(moved.hasTime)
        #expect(moved.date == at(9, daysFromToday: 1))
    }

    @Test func nextUpGroupsByDayWithOverdueFirst() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func item(_ id: String, days: Int, parent: String? = nil) -> ReminderItem {
            var item = ReminderItem(id: id, title: id, listID: "l", listTitle: "L", listColor: .blue,
                                    due: calendar.date(byAdding: .day, value: days, to: today), parentID: parent)
            item.depth = parent == nil ? 0 : 1
            return item
        }
        let section = ReminderSection(list: SmartList.nextUp, items: [
            item("late", days: -2), item("late2", days: -1), item("now", days: 0), item("sub", days: 3, parent: "now"),
            item("soon", days: 1), item("later", days: 20),
        ])
        let entries = section.entries(foldedParents: [], foldedSections: [], now: Date())
        let titles = entries.compactMap { entry -> String? in
            if case .day(let title, _, _) = entry { title } else { nil }
        }
        #expect(titles.count == 4)
        #expect(titles.prefix(3) == ["Overdue", "Today", "Tomorrow"])
        // One title over both late reminders, and the sub-task stays under its parent.
        #expect(entries.count == 6 + 4)
        if case .item(let second) = entries[2] { #expect(second.id == "late2") } else { Issue.record("not an item") }
        if case .item(let child) = entries[5] { #expect(child.id == "sub") } else { Issue.record("not an item") }
    }

    @Test func nextUpNeverRepeatsATitle() {
        let calendar = Calendar.current
        let now = Date()
        func item(_ id: String, due: Date, hasTime: Bool) -> ReminderItem {
            var item = ReminderItem(id: id, title: id, listID: "l", listTitle: "L", listColor: .blue, due: due)
            item.dueHasTime = hasTime
            return item
        }
        // A day-only reminder for today sorts between two late ones, which must still share one title.
        let section = ReminderSection(list: SmartList.nextUp, items: [
            item("a", due: now.addingTimeInterval(-90_000), hasTime: true),
            item("b", due: calendar.startOfDay(for: now), hasTime: false),
            item("c", due: now.addingTimeInterval(-60), hasTime: true),
        ])
        let entries = section.entries(foldedParents: [], foldedSections: [], now: now)
        let ids = entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        guard case .day(let first, true, _) = entries[0] else { Issue.record("Overdue should come first"); return }
        #expect(first == "Overdue")
        #expect(entries.count == 5)
    }

    @Test func dayHeadings() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        #expect(dayHeading(for: today) == "Today")
        #expect(dayHeading(for: calendar.date(byAdding: .day, value: 1, to: today)!) == "Tomorrow")
        let inThree = calendar.date(byAdding: .day, value: 3, to: today)!
        #expect(dayHeading(for: inThree) == inThree.formatted(.dateTime.weekday(.wide)))
    }

    @Test func nextUpIsListedAndCannotBeAddedTo() {
        #expect(SmartList.allLists.contains { $0.id == SmartList.nextUp.id })
        #expect(!SmartList.canAdd(to: SmartList.nextUp))
        #expect(SmartList.sortsByTime(SmartList.nextUp))
    }
}

@MainActor
struct DropResolverTests {
    private let list = ReminderList(id: "work", title: "Work", color: .blue)
    private let other = ReminderList(id: "home", title: "Home", color: .green)

    private func item(_ id: String, in list: ReminderList, section: String? = nil, parent: String? = nil, flagged: Bool = false) -> ReminderItem {
        var item = ReminderItem(id: id, title: id, listID: list.id, listTitle: list.title, listColor: list.color, parentID: parent)
        item.isFlagged = flagged
        item.depth = parent == nil ? 0 : 1
        item.sectionID = section
        item.sectionTitle = section
        return item
    }

    /// Lays a list out top to bottom the way the dropdown does, starting at `y`, and records where everything is.
    private func layout(_ section: ReminderSection, frames: RowFrames, from y: CGFloat) -> CGFloat {
        var y = y
        frames.headers[section.id] = CGRect(x: 0, y: y, width: 296, height: 30); y += 32
        for entry in section.entries(foldedParents: [], foldedSections: []) {
            switch entry {
            case .heading(let info, _, _):
                frames.headings[section.id + "|" + info.id] = CGRect(x: 0, y: y, width: 296, height: 28); y += 30
            case .day:
                y += 30
            case .noSection:
                frames.headings[section.id + "|none"] = CGRect(x: 0, y: y, width: 296, height: 28); y += 30
            case .item(let item):
                frames.rows[section.id + "|" + item.id] = CGRect(x: 0, y: y, width: 296, height: 36); y += 38
            }
        }
        return y + 14
    }

    private func resolver(_ sections: [ReminderSection]) -> DropResolver {
        let frames = RowFrames()
        var y: CGFloat = 0
        for section in sections { y = layout(section, frames: frames, from: y) }
        return DropResolver(sections: sections, collapsedLists: [], collapsedParents: [], collapsedSections: [], frames: frames,
                            hasSubtasks: { moving in sections.flatMap(\.items).contains { $0.parentID == moving.id } })
    }

    @Test func reorderingWorksDownAsWellAsUp() throws {
        let a = item("a", in: list), b = item("b", in: list), c = item("c", in: list)
        let resolver = resolver([ReminderSection(list: list, items: [a, b, c])])
        let rowC = try #require(resolver.frames.rows["work|c"])
        let rowA = try #require(resolver.frames.rows["work|a"])

        // Down: the lower half of the last row goes after it, the top edge before it.
        let down = try #require(resolver.target(moving: a, at: CGPoint(x: 100, y: rowC.maxY - 3)))
        guard case .reorder(let target, let after) = down.action else { Issue.record("expected a reorder"); return }
        #expect(target.id == "c" && after)
        let before = try #require(resolver.target(moving: a, at: CGPoint(x: 100, y: rowC.minY + 2)))
        guard case .reorder(_, let afterTop) = before.action else { Issue.record("expected a reorder"); return }
        #expect(!afterTop)

        // Up, the same way.
        let up = try #require(resolver.target(moving: c, at: CGPoint(x: 100, y: rowA.minY + 2)))
        guard case .reorder(let upTarget, let upAfter) = up.action else { Issue.record("expected a reorder"); return }
        #expect(upTarget.id == "a" && !upAfter)
        // Over itself nothing happens.
        #expect(resolver.target(moving: a, at: CGPoint(x: 100, y: rowA.midY)) == nil)
    }

    @Test func subtasksReorderAmongTheirSiblings() throws {
        let parent = item("p", in: list), first = item("k1", in: list, parent: "p"), second = item("k2", in: list, parent: "p")
        let resolver = resolver([ReminderSection(list: list, items: [parent, first, second])])
        let row = try #require(resolver.frames.rows["work|k2"])
        let result = try #require(resolver.target(moving: first, at: CGPoint(x: 100, y: row.maxY - 3)))
        guard case .reorderSubtask(let target, let after) = result.action else { Issue.record("expected a sub-task reorder"); return }
        #expect(target.id == "k2" && after)
        // The middle of a sibling is still just an order, never a new parent.
        let middle = try #require(resolver.target(moving: first, at: CGPoint(x: 100, y: row.midY)))
        guard case .reorderSubtask = middle.action else { Issue.record("expected a sub-task reorder"); return }
    }

    @Test func middleOfARowMakesASubtask() throws {
        let a = item("a", in: list), b = item("b", in: list)
        let resolver = resolver([ReminderSection(list: list, items: [a, b])])
        let rowB = try #require(resolver.frames.rows["work|b"])
        let result = try #require(resolver.target(moving: a, at: CGPoint(x: 100, y: rowB.midY)))
        guard case .subtask(let parent) = result.action else { Issue.record("expected a sub-task"); return }
        #expect(parent.id == "b")
    }

    @Test func sectionsBelowTheReminderTakeIt() throws {
        let a1 = item("a1", in: list, section: "A"), a2 = item("a2", in: list, section: "A"), b1 = item("b1", in: list, section: "B")
        let sections = [ReminderKit.ListSection(id: "A", title: "A", index: 0), ReminderKit.ListSection(id: "B", title: "B", index: 1)]
        let resolver = resolver([ReminderSection(list: list, items: [a1, a2, b1], sections: sections)])
        let heading = try #require(resolver.frames.headings["work|B"])
        let onHeading = try #require(resolver.target(moving: a1, at: CGPoint(x: 100, y: heading.midY)))
        guard case .section(let id, _) = onHeading.action else { Issue.record("expected a section move"); return }
        #expect(id == "B")

        let rowB1 = try #require(resolver.frames.rows["work|b1"])
        let onRow = try #require(resolver.target(moving: a1, at: CGPoint(x: 100, y: rowB1.midY)))
        guard case .section(let rowID, _) = onRow.action else { Issue.record("expected a section move"); return }
        #expect(rowID == "B")
        #expect(onRow.rect == heading)   // the heading lights up, not the reminder

        // And up again, from B into A.
        let headingA = try #require(resolver.frames.headings["work|A"])
        let back = try #require(resolver.target(moving: b1, at: CGPoint(x: 100, y: headingA.midY)))
        guard case .section(let backID, _) = back.action else { Issue.record("expected a section move"); return }
        #expect(backID == "A")
    }

    @Test func theNoSectionTitleTakesAReminderOutOfItsSection() throws {
        let a = item("a", in: list, section: "A"), loose = item("l", in: list)
        let sections = [ReminderKit.ListSection(id: "A", title: "A", index: 0)]
        let resolver = resolver([ReminderSection(list: list, items: [a, loose], sections: sections)])
        let title = try #require(resolver.frames.headings["work|none"])
        let result = try #require(resolver.target(moving: a, at: CGPoint(x: 100, y: title.midY)))
        guard case .section(let id, _) = result.action else { Issue.record("expected a section move"); return }
        #expect(id == nil)
        // A reminder that is in no section already has nothing to do there.
        #expect(resolver.target(moving: loose, at: CGPoint(x: 100, y: title.midY)) == nil)
    }

    @Test func aReminderCanLeaveItsSectionOnTheListName() throws {
        let a1 = item("a1", in: list, section: "A")
        let sections = [ReminderKit.ListSection(id: "A", title: "A", index: 0)]
        let resolver = resolver([ReminderSection(list: list, items: [a1], sections: sections)])
        let header = try #require(resolver.frames.headers["work"])
        let result = try #require(resolver.target(moving: a1, at: CGPoint(x: 100, y: header.midY)))
        guard case .section(let id, _) = result.action else { Issue.record("expected a section move"); return }
        #expect(id == nil)
    }

    @Test func anotherListBelowTakesTheReminder() throws {
        let a = item("a", in: list), h = item("h", in: other)
        let resolver = resolver([ReminderSection(list: list, items: [a]), ReminderSection(list: other, items: [h])])
        let header = try #require(resolver.frames.headers["home"])
        let onHeader = try #require(resolver.target(moving: a, at: CGPoint(x: 100, y: header.midY)))
        guard case .move(let moved) = onHeader.action else { Issue.record("expected a move"); return }
        #expect(moved.id == "home")
        // On one of its reminders, the list's name lights up.
        let row = try #require(resolver.frames.rows["home|h"])
        let onRow = try #require(resolver.target(moving: a, at: CGPoint(x: 100, y: row.midY)))
        #expect(onRow.rect == header)
    }

    @Test func subtasksCanBeTakenOutOrMovedToAnotherParent() throws {
        let parent = item("p", in: list), child = item("k", in: list, parent: "p"), sibling = item("s", in: list)
        let resolver = resolver([ReminderSection(list: list, items: [parent, child, sibling])])
        let rowS = try #require(resolver.frames.rows["work|s"])
        let rowP = try #require(resolver.frames.rows["work|p"])
        let header = try #require(resolver.frames.headers["work"])

        let edge = try #require(resolver.target(moving: child, at: CGPoint(x: 100, y: rowS.maxY - 3)))
        guard case .promote(let anchor, let after) = edge.action else { Issue.record("expected a promotion"); return }
        #expect(anchor?.id == "s" && after)
        let middle = try #require(resolver.target(moving: child, at: CGPoint(x: 100, y: rowS.midY)))
        guard case .subtask(let newParent) = middle.action else { Issue.record("expected a new parent"); return }
        #expect(newParent.id == "s")
        // Over its own parent's middle nothing happens; the edges take it out next to the parent.
        #expect(resolver.target(moving: child, at: CGPoint(x: 100, y: rowP.midY)) == nil)
        let aside = try #require(resolver.target(moving: child, at: CGPoint(x: 100, y: rowP.minY + 2)))
        guard case .promote(let beside, _) = aside.action else { Issue.record("expected a promotion"); return }
        #expect(beside?.id == "p")
        // The list's name takes it out of the parent in place.
        let onName = try #require(resolver.target(moving: child, at: CGPoint(x: 100, y: header.midY)))
        guard case .promote(let none, _) = onName.action else { Issue.record("expected a promotion"); return }
        #expect(none == nil)
    }

    @Test func smartListsTakeFlagsAndDatesOnly() throws {
        let a = item("a", in: list)
        var flagged = a; flagged.isFlagged = true
        let resolver = resolver([ReminderSection(list: SmartList.today, items: [a]), ReminderSection(list: SmartList.flagged, items: [flagged]),
                                 ReminderSection(list: SmartList.scheduled, items: [a])])
        let today = try #require(resolver.frames.headers[SmartList.today.id])
        let flagHeader = try #require(resolver.frames.headers[SmartList.flagged.id])
        let scheduled = try #require(resolver.frames.headers[SmartList.scheduled.id])
        guard case .today? = resolver.target(moving: a, at: CGPoint(x: 100, y: today.midY))?.action else { Issue.record("expected Today"); return }
        guard case .flag? = resolver.target(moving: a, at: CGPoint(x: 100, y: flagHeader.midY))?.action else { Issue.record("expected a flag"); return }
        #expect(resolver.target(moving: flagged, at: CGPoint(x: 100, y: flagHeader.midY)) == nil)
        #expect(resolver.target(moving: a, at: CGPoint(x: 100, y: scheduled.midY)) == nil)
    }

    @Test func sectionsAndListsFindTheirSlot() throws {
        let sections = [ReminderKit.ListSection(id: "A", title: "A", index: 0), ReminderKit.ListSection(id: "B", title: "B", index: 1),
                        ReminderKit.ListSection(id: "C", title: "C", index: 2)]
        let items = [item("a", in: list, section: "A"), item("b", in: list, section: "B"), item("c", in: list, section: "C")]
        let resolver = resolver([ReminderSection(list: list, items: items, sections: sections), ReminderSection(list: other, items: [item("h", in: other)])])
        let headingC = try #require(resolver.frames.headings["work|C"])
        // A carried down past C lands last.
        let last = try #require(resolver.sectionSlot(moving: sections[0], in: "work", at: CGPoint(x: 100, y: headingC.maxY + 40)))
        #expect(last.index == 2)
        let headingB = try #require(resolver.frames.headings["work|B"])
        let first = try #require(resolver.sectionSlot(moving: sections[2], in: "work", at: CGPoint(x: 100, y: headingB.minY - 4)))
        #expect(first.index == 1)

        let homeHeader = try #require(resolver.frames.headers["home"])
        let after = try #require(resolver.listSlot(moving: "work", at: CGPoint(x: 100, y: homeHeader.maxY + 60)))
        #expect(after.target == "home" && after.after)
        let workHeader = try #require(resolver.frames.headers["work"])
        let before = try #require(resolver.listSlot(moving: "home", at: CGPoint(x: 100, y: workHeader.minY - 2)))
        #expect(before.target == "work" && !before.after)
    }
}

@MainActor
struct FocusTests {
    @Test func aBoxTakesFocusAsSoonAsItAppears() async throws {
        let field = HighlightedTextField(text: .constant(""), placeholder: "Name", tokens: [], color: { _ in .clear },
                                         focusTrigger: 1, onSubmit: {}, onTab: { true })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 30), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: field.frame(width: 240, height: 30))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        #expect(window.firstResponder is NSTextView)
    }

    @Test func renamingSelectsTheWholeName() async throws {
        let field = HighlightedTextField(text: .constant("Groceries"), placeholder: "Name", tokens: [], color: { _ in .clear },
                                         focusTrigger: 1, onSubmit: {}, onTab: { true }, selectsAllOnFocus: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 30), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: field.frame(width: 240, height: 30))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 9))
    }
}

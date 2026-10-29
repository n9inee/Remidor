//
//  TaskModel.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import AppKit
import EventKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Remidor", category: "reminders")

/// Owns the EventKit store, the lists shown in the menu and the focus-timer state.
@MainActor @Observable
final class TaskModel {
    static let shared = TaskModel()

    private let store = EKEventStore()

    // MARK: Loaded data

    var sections: [ReminderSection] = []
    var lists: [ReminderList] = []
    /// Tags known from Reminders and from `#tags` in titles, for autocomplete.
    var allTags: [String] = []
    var hasAccess = false
    var accessDenied = false

    // MARK: Timer state

    var phase: Phase = .idle
    var now = Date()
    var runTotal: TimeInterval = 1

    var remaining: TimeInterval {
        if case .running(_, let end) = phase { return max(0, end.timeIntervalSince(now)) }
        return 0
    }

    // MARK: Undo state

    /// The last few completed tasks, newest first.
    var recentlyCompleted: [ReminderItem] = []
    /// The latest completion, shown in a banner for a few seconds.
    var undoBannerItem: ReminderItem?
    /// False for repeating tasks. Reminders keeps the original, moves it to its next date and logs a
    /// separate completed copy, so there is nothing safe to un-complete.
    var undoBannerCanUndo = true

    // MARK: Errors

    /// The latest failure, shown in a banner for a few seconds.
    var errorMessage: String?

    // MARK: Settings (saved between launches)

    var defaultMinutes: Int = {
        let saved = UserDefaults.standard.integer(forKey: DefaultsKey.defaultMinutes)
        return saved > 0 ? saved : 30
    }() {
        didSet { UserDefaults.standard.set(defaultMinutes, forKey: DefaultsKey.defaultMinutes) }
    }

    /// The weekday "Next week" lands on, and the one "Weekend" lands on (1 is Sunday ... 7 is Saturday).
    var weekStart: Int = UserDefaults.standard.object(forKey: DefaultsKey.weekStart) as? Int ?? 2 {
        didSet { UserDefaults.standard.set(weekStart, forKey: DefaultsKey.weekStart) }
    }

    var weekendStart: Int = UserDefaults.standard.object(forKey: DefaultsKey.weekendStart) as? Int ?? 7 {
        didSet { UserDefaults.standard.set(weekendStart, forKey: DefaultsKey.weekendStart) }
    }

    /// Where late reminders can be moved to, for the Reschedule menus.
    var rescheduleChoices: [(title: String, day: Date)] {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return [("Today", Date()), ("Tomorrow", tomorrow), ("Weekend", weekendDay), ("Next Week", nextWeekDay)]
    }

    var nextWeekDay: Date { ReminderEditing.nextWeekStart(weekStart) }
    var weekendDay: Date { ReminderEditing.weekend(startingOn: weekendStart) }

    var sortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.sortOrder) ?? "") ?? .dueDate {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKey.sortOrder)
            scheduleRefresh()
        }
    }

    /// Sort orders chosen for single lists. A list without one follows `sortOrder`.
    var listSortOrders: [String: SortOrder] = {
        let saved = UserDefaults.standard.dictionary(forKey: DefaultsKey.listSortOrders) as? [String: String] ?? [:]
        return saved.compactMapValues(SortOrder.init(rawValue:))
    }() {
        didSet {
            UserDefaults.standard.set(listSortOrders.mapValues(\.rawValue), forKey: DefaultsKey.listSortOrders)
            scheduleRefresh()
        }
    }

    func sortOrder(for list: ReminderList) -> SortOrder { listSortOrders[list.id] ?? sortOrder }

    /// Orders chosen for the sub-tasks of single reminders, by the parent's id. Without one, sub-tasks follow
    /// their list's order.
    var subtaskSortOrders: [String: SortOrder] = {
        let saved = UserDefaults.standard.dictionary(forKey: DefaultsKey.subtaskSortOrders) as? [String: String] ?? [:]
        return saved.compactMapValues(SortOrder.init(rawValue:))
    }() {
        didSet {
            UserDefaults.standard.set(subtaskSortOrders.mapValues(\.rawValue), forKey: DefaultsKey.subtaskSortOrders)
            scheduleRefresh()
        }
    }

    /// nil goes back to the list's order.
    func setSubtaskOrder(_ order: SortOrder?, for parent: ReminderItem) {
        subtaskSortOrders[parent.id] = order
    }

    /// How many lists have an order of their own that differs from the common one.
    var listsWithOwnOrder: Int {
        lists.filter { !$0.isSmart || !SmartList.sortsByTime($0) }.filter { listSortOrders[$0.id].map { $0 != sortOrder } ?? false }.count
    }

    /// Makes every list follow the common order again, forgetting the orders chosen for single lists.
    func applySortOrderToAllLists() {
        guard !listSortOrders.isEmpty else { return }
        listSortOrders = [:]
    }

    /// nil goes back to the common order.
    func setSortOrder(_ order: SortOrder?, for list: ReminderList) {
        listSortOrders[list.id] = order
    }

    /// Parents whose sub-tasks are folded away in the dropdown.
    var collapsedParentIDs = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.collapsedParents) ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedParentIDs), forKey: DefaultsKey.collapsedParents) }
    }

    /// List sections folded shut in the dropdown.
    var collapsedSectionIDs = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.collapsedSections) ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedSectionIDs), forKey: DefaultsKey.collapsedSections) }
    }

    func toggleSection(_ id: String) {
        if collapsedSectionIDs.contains(id) { collapsedSectionIDs.remove(id) } else { collapsedSectionIDs.insert(id) }
    }

    func toggleSubtasks(of item: ReminderItem) {
        if collapsedParentIDs.contains(item.id) { collapsedParentIDs.remove(item.id) } else { collapsedParentIDs.insert(item.id) }
    }

    /// nil until the user chooses; then every regular list is shown and smart lists are opt-in.
    var selectedListIDs: Set<String>? = UserDefaults.standard.stringArray(forKey: DefaultsKey.selectedLists).map(Set.init) {
        didSet {
            UserDefaults.standard.set(selectedListIDs.map(Array.init), forKey: DefaultsKey.selectedLists)
            scheduleRefresh()
        }
    }

    /// The order of all lists, smart ones included, as arranged in Settings.
    var listOrder: [String] = UserDefaults.standard.stringArray(forKey: DefaultsKey.listOrder) ?? [] {
        didSet { UserDefaults.standard.set(listOrder, forKey: DefaultsKey.listOrder) }
    }

    /// Lists folded shut in the dropdown.
    var collapsedListIDs = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.collapsedLists) ?? []) {
        didSet { UserDefaults.standard.set(Array(collapsedListIDs), forKey: DefaultsKey.collapsedLists) }
    }

    /// The list chosen with the star in Settings.
    var preferredListID = UserDefaults.standard.string(forKey: DefaultsKey.preferredList) {
        didSet { UserDefaults.standard.set(preferredListID, forKey: DefaultsKey.preferredList) }
    }

    /// Where new reminders go: the starred list, else "Inbox", else the system default list.
    var defaultListID: String? {
        if let id = preferredListID, lists.contains(where: { $0.id == id && !$0.isSmart }) { return id }
        return fallbackListID
    }

    // MARK: Private state

    private var fallbackListID: String?
    /// Every open reminder from the latest fetch, whatever lists are shown. Used to find sub-tasks.
    @ObservationIgnored private var openItems: [ReminderItem] = []
    /// The sub-tasks that were completed together with a parent, so undoing the parent brings them back.
    @ObservationIgnored private var completedSubtasks: [String: [String]] = [:]
    /// Reminders just completed or deleted. They stay hidden until a fetch confirms the change,
    /// so a stale fetch can't bring them back.
    @ObservationIgnored private var pendingRemovals = [String: Date]()
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?
    @ObservationIgnored private var errorExpiry: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var tickLoop: Task<Void, Never>?

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        refreshLoop = Task { [weak self] in
            await self?.requestAccess()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.refresh()
            }
        }
    }

    // MARK: Access and loading

    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        hasAccess = granted
        accessDenied = !granted
        if granted { await refresh() }
    }

    func scheduleRefresh() {
        Task { await refresh() }
    }

    /// Reloads the lists and reminders. A refresh that starts while another is running is folded into
    /// one follow-up pass, so an older fetch can never overwrite a newer one.
    func refresh() async {
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshQueued = false
            await loadReminders()
        } while refreshQueued
    }

    private func loadReminders() async {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            break
        case .notDetermined:
            return   // requestAccess() is asking; it refreshes once the answer is in
        default:
            // Declined, restricted, or taken away while the app was running.
            hasAccess = false
            accessDenied = true
            sections = []
            return
        }
        hasAccess = true
        accessDenied = false

        store.refreshSourcesIfNecessary()
        let calendars = store.calendars(for: .reminder)
        updateLists(from: calendars)

        // The order and sections the user made in Reminders are only read when something needs them.
        let selected = lists.filter { isSelected($0) && !$0.isSmart }
        let needsManual = lists.contains { isSelected($0) && sortOrder(for: $0) == .manual }
            || subtaskSortOrders.values.contains(.manual)
        // Looked up again by identifier, because the list objects can hold on to an older arrangement.
        let manual = needsManual ? Dictionary(calendars.map { ($0.calendarIdentifier, ReminderKit.manualOrder(of: store.calendar(withIdentifier: $0.calendarIdentifier) ?? $0)) },
                                              uniquingKeysWith: { first, _ in first }) : [:]
        let sectionLookups = ReminderKit.sectionLookup(for: calendars.filter { c in selected.contains { $0.id == c.calendarIdentifier } },
                                                       in: store)

        // If the fetch fails, keep showing what is already there instead of an empty list.
        guard let items = await fetchIncomplete(in: calendars, manual: manual, sections: sectionLookups) else { return }
        openItems = items

        // Drop a pending removal once a fetch no longer returns the reminder, or after 10 seconds.
        let fetchedIDs = Set(items.map(\.id))
        pendingRemovals = pendingRemovals.filter { fetchedIDs.contains($0.key) && Date().timeIntervalSince($0.value) < 10 }
        let visible = items.filter { pendingRemovals[$0.id] == nil }

        allTags = Self.knownTags(in: items)
        sections = makeSections(from: visible, listSections: sectionLookups.mapValues(\.allSections))
    }

    private func updateLists(from calendars: [EKCalendar]) {
        // New reminders go to "Inbox" when such a list exists, otherwise to the system default list.
        let inbox = calendars.first { $0.title.localizedCaseInsensitiveCompare("Inbox") == .orderedSame }
        fallbackListID = (inbox ?? store.defaultCalendarForNewReminders())?.calendarIdentifier

        let all = SmartList.allLists + calendars.map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor))
        }
        // Lists the user has placed come first in that order; new lists keep their natural order after them.
        let position = Dictionary(listOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        lists = all.enumerated()
            .sorted { (position[$0.element.id] ?? .max, $0.offset) < (position[$1.element.id] ?? .max, $1.offset) }
            .map(\.element)
    }

    private func fetchIncomplete(in calendars: [EKCalendar], manual: [String: [String: Int]],
                                 sections: [String: ReminderKit.SectionLookup]) async -> [ReminderItem]? {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let all = reminders else {
                    log.error("Fetching reminders failed")
                    continuation.resume(returning: nil)
                    return
                }
                let known = Dictionary(all.map { ($0.calendarItemIdentifier.uppercased(), $0.calendarItemIdentifier) },
                                       uniquingKeysWith: { first, _ in first })
                continuation.resume(returning: all.map { r in
                    let section = sections[r.calendar.calendarIdentifier]?.section(of: r)
                    return ReminderItem(
                        id: r.calendarItemIdentifier,
                        title: r.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled",
                        listID: r.calendar.calendarIdentifier,
                        listTitle: r.calendar.title,
                        listColor: Color(cgColor: r.calendar.cgColor),
                        due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        dueHasTime: r.dueDateComponents?.hour != nil,
                        isRepeating: r.hasRecurrenceRules,
                        recurrence: r.recurrenceRules?.first.flatMap(Recurrence.init(rule:)),
                        isFlagged: ReminderKit.isFlagged(r),
                        priority: r.priority,
                        created: r.creationDate,
                        notes: r.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        url: r.url,
                        tags: ReminderKit.tags(of: r),
                        parentID: ReminderKit.parentIdentifier(of: r, known: known),
                        manualIndex: manual[r.calendar.calendarIdentifier]?[r.calendarItemIdentifier.uppercased()] ?? .max,
                        sectionIndex: section?.index ?? -1,
                        sectionTitle: section?.title,
                        sectionID: section?.id
                    )
                })
            }
        }
    }

    /// Everything that is late, then the next few reminders that aren't.
    private func nextUpItems(from items: [ReminderItem]) -> [ReminderItem] {
        let dated = items.filter { $0.due != nil }.sortedByDueTime()
        return dated.filter { isOverdue($0) } + dated.filter { !isOverdue($0) }.prefix(SmartList.nextUpCount)
    }

    private func makeSections(from items: [ReminderItem], listSections: [String: [ReminderKit.ListSection]]) -> [ReminderSection] {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        let byList = Dictionary(grouping: items, by: \.listID)

        return lists.filter(isSelected).compactMap { list in
            let matching: [ReminderItem] = switch list.id {
            case SmartList.today.id: items.filter { ($0.due ?? .distantFuture) < endOfToday }
            case SmartList.nextUp.id: nextUpItems(from: items)
            case SmartList.scheduled.id: items.filter { $0.due != nil }
            case SmartList.flagged.id: items.filter(\.isFlagged)
            case SmartList.all.id: items
            default: byList[list.id] ?? []
            }
            // Smart lists only show when they have something. Your own lists always do, even when empty.
            guard !matching.isEmpty || !list.isSmart else { return nil }
            let order = sortOrder(for: list)
            var ordered: [ReminderItem]
            if SmartList.sortsByTime(list) {
                ordered = matching.sortedByDueTime()
            } else if order == .manual && list.isSmart {
                // Across several lists, manual means the lists in their order, each in its own arrangement.
                let position = Dictionary(lists.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
                ordered = matching.sorted(by: .manual).enumerated()
                    .sorted { (position[$0.element.listID] ?? 0, $0.offset) < (position[$1.element.listID] ?? 0, $1.offset) }
                    .map(\.element)
            } else {
                ordered = matching.sorted(by: order)
            }
            // Sections only exist inside one list.
            if !list.isSmart { ordered = ordered.groupedBySection() }
            return ReminderSection(list: list, items: ordered.nestingSubtasks(childOrder: { subtaskSortOrders[$0] }), sections: list.isSmart ? [] : listSections[list.id] ?? [])
        }
    }

    private static func knownTags(in items: [ReminderItem]) -> [String] {
        let fromReminders = items.flatMap(\.tags)
        let fromTitles = QuickAddParser.tags(in: items.map(\.title))
        var seen = Set<String>()
        return (fromReminders + fromTitles)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: List settings

    func isSelected(_ list: ReminderList) -> Bool {
        selectedListIDs?.contains(list.id) ?? !list.isSmart
    }

    func setList(_ list: ReminderList, selected: Bool) {
        var set = selectedListIDs ?? Set(lists.filter { !$0.isSmart }.map(\.id))
        if selected { set.insert(list.id) } else { set.remove(list.id) }
        selectedListIDs = set
    }

    func toggleCollapsed(_ list: ReminderList) {
        if collapsedListIDs.contains(list.id) { collapsedListIDs.remove(list.id) } else { collapsedListIDs.insert(list.id) }
    }

    func moveLists(from source: IndexSet, to destination: Int) {
        var reordered = lists
        reordered.move(fromOffsets: source, toOffset: destination)
        lists = reordered
        listOrder = reordered.map(\.id)
        scheduleRefresh()
    }

    /// Puts a list right before or after another one. The order is the one used everywhere, Settings included.
    func moveList(_ id: String, nextTo targetID: String, after: Bool) {
        guard id != targetID, let from = lists.firstIndex(where: { $0.id == id }) else { return }
        var reordered = lists
        let moving = reordered.remove(at: from)
        guard let to = reordered.firstIndex(where: { $0.id == targetID }) else { return }
        reordered.insert(moving, at: after ? to + 1 : to)
        lists = reordered
        listOrder = reordered.map(\.id)
        scheduleRefresh()
    }

    // MARK: Changing reminders

    /// Adds a reminder. With a parent it becomes that reminder's sub-task, and with a section id it is put into
    /// that section of its list.
    func addReminder(_ new: NewReminder, parent: ReminderItem? = nil, sectionID: String? = nil) async -> Bool {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            report("Remidor can't reach your reminders. Allow access in System Settings → Privacy & Security → Reminders.")
            return false
        }
        guard let calendar = calendar(withID: new.listID) ?? calendar(withID: defaultListID) ?? store.defaultCalendarForNewReminders() else {
            report("There is no list to add the reminder to.")
            return false
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = new.title
        reminder.priority = new.priority ?? 0
        if let due = new.due { ReminderEditing.setDue(due, hasTime: new.hasTime, on: reminder) }
        if let recurrence = new.recurrence { reminder.addRecurrenceRule(recurrence.makeRule()) }
        guard save(reminder, action: "add") else {
            report("Couldn't add the reminder. Please try again.")
            return false
        }
        // A flag can only be set once the reminder exists.
        if new.flagged, !ReminderKit.setFlagged(true, for: reminder, in: store) {
            report("Added “\(new.title)”, but couldn't flag it.")
        }
        // So can its place under a parent or in a section.
        if let parent {
            if let parentReminder = self.reminder(withID: parent.id), ReminderKit.makeSubtask(reminder, of: parentReminder, in: store) {
                collapsedParentIDs.remove(parent.id)
            } else {
                report("Added “\(new.title)”, but couldn't make it a sub-task.")
            }
        } else if let sectionID, !ReminderKit.move(reminder, toSection: sectionID, in: calendar, in: store) {
            report("Added “\(new.title)”, but couldn't put it in that section.")
        }
        await refresh()
        return true
    }

    /// The reminder one step up (-1) or down (+1) among those at the same level and in the same section of
    /// its own list, as shown. A sub-task is compared with the other sub-tasks of its parent.
    func neighbor(of item: ReminderItem, offset: Int) -> ReminderItem? {
        guard let section = sections.first(where: { $0.list.id == item.listID }) else { return nil }
        let siblings = section.items.filter { $0.parentID == item.parentID && $0.sectionID == item.sectionID }
        guard let index = siblings.firstIndex(where: { $0.id == item.id }), siblings.indices.contains(index + offset) else { return nil }
        return siblings[index + offset]
    }

    /// Moves a reminder one step up or down in its list, which puts the list in manual order. A sub-task moves
    /// among its parent's sub-tasks, and puts only those in manual order.
    func moveReminder(_ item: ReminderItem, by offset: Int) {
        guard let neighbor = neighbor(of: item, offset: offset) else { return }
        if item.parentID != nil { reorderSubtask(item, nextTo: neighbor, after: offset > 0) } else { reorder(item, nextTo: neighbor, after: offset > 0) }
    }

    /// Puts a sub-task next to another sub-task of the same parent. By hand means manual: that parent's
    /// sub-tasks switch to manual order, whatever the list does.
    func reorderSubtask(_ item: ReminderItem, nextTo target: ReminderItem, after: Bool) {
        guard let parentID = item.parentID, target.parentID == parentID, item.id != target.id else { return }
        guard let child = reminder(withID: item.id), let parent = reminder(withID: parentID), let anchor = reminder(withID: target.id) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        guard ReminderKit.moveSubtask(child, of: parent, nextTo: anchor, after: after, in: store) else {
            report("Couldn't change the order of “\(item.title)”.")
            scheduleRefresh()
            return
        }
        if subtaskSortOrders[parentID] != .manual {
            subtaskSortOrders[parentID] = .manual   // refreshes by itself
        } else {
            scheduleRefresh()
        }
    }

    /// Takes a sub-task out of its parent, leaving it at the top level next to that parent. Does nothing for
    /// a reminder that isn't a sub-task. Returns false if it failed.
    @discardableResult
    private func detach(_ item: ReminderItem) -> Bool {
        guard let parentID = item.parentID else { return true }
        guard let child = reminder(withID: item.id), let parent = reminder(withID: parentID) else { return false }
        return ReminderKit.makeTopLevel(child, nextTo: parent, after: true, in: store)
    }

    /// Takes a sub-task out of its parent. With a reminder to go next to, it is placed there, which also puts
    /// the list in manual order so the place is kept.
    func promote(_ item: ReminderItem, nextTo target: ReminderItem?, after: Bool) {
        guard let parentID = item.parentID else { return }
        guard let child = reminder(withID: item.id),
              let anchor = reminder(withID: target?.id ?? parentID) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        guard ReminderKit.makeTopLevel(child, nextTo: anchor, after: target == nil ? true : after, in: store) else {
            report("Couldn't take “\(item.title)” out of its parent.")
            scheduleRefresh()
            return
        }
        if target != nil, let list = lists.first(where: { $0.id == item.listID }), sortOrder(for: list) != .manual {
            setSortOrder(.manual, for: list)   // refreshes by itself
        } else {
            scheduleRefresh()
        }
    }

    /// Moves a reminder to another list.
    func move(_ item: ReminderItem, toListID id: String) {
        guard item.listID != id else { return }
        // A sub-task can't stay a sub-task in another list.
        if item.parentID != nil, !detach(item) {
            report("Couldn't move “\(item.title)”.")
            scheduleRefresh()
            return
        }
        guard let reminder = reminder(withID: item.id), let target = calendar(withID: id) else {
            report("That reminder or list no longer exists.")
            scheduleRefresh()
            return
        }
        reminder.calendar = target
        if !save(reminder, action: "move") { report("Couldn't move “\(item.title)”.") }
        // Sub-tasks go along with their parent.
        for child in openItems where child.parentID == item.id {
            if let stored = self.reminder(withID: child.id) {
                stored.calendar = target
                _ = save(stored, action: "move")
            }
        }
        scheduleRefresh()
    }

    /// The open reminder with this id, from the latest fetch.
    func openItem(withID id: String) -> ReminderItem? {
        openItems.first { $0.id == id }
    }

    /// Puts a reminder next to another one of the same list, and switches that list to manual order so
    /// the new position is what the dropdown shows.
    func reorder(_ item: ReminderItem, nextTo target: ReminderItem, after: Bool) {
        guard item.listID == target.listID, item.id != target.id else { return }
        guard let moving = reminder(withID: item.id), let anchor = reminder(withID: target.id) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        guard ReminderKit.move(moving, nextTo: anchor, after: after, in: store) else {
            report("Couldn't change the order of “\(item.title)”.")
            scheduleRefresh()
            return
        }
        if let list = lists.first(where: { $0.id == item.listID }), sortOrder(for: list) != .manual {
            setSortOrder(.manual, for: list)   // refreshes by itself
        } else {
            scheduleRefresh()
        }
    }

    /// Saves what was edited in place: title, date, priority, flag and list.
    func update(_ item: ReminderItem, to new: NewReminder) {
        guard let reminder = reminder(withID: item.id) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        if new.title != item.title { reminder.title = new.title }
        if new.due != item.due || (new.due != nil && new.hasTime != item.dueHasTime) {
            ReminderEditing.setDue(new.due, hasTime: new.hasTime, on: reminder)
        }
        reminder.priority = new.priority ?? 0
        // Only touched when it was changed, so a repeat Remidor can't describe stays as it is.
        if new.recurrence != item.recurrence {
            for rule in reminder.recurrenceRules ?? [] { reminder.removeRecurrenceRule(rule) }
            if let recurrence = new.recurrence { reminder.addRecurrenceRule(recurrence.makeRule()) }
        }
        let moved = new.listID.flatMap { $0 == item.listID ? nil : calendar(withID: $0) }
        if let moved { reminder.calendar = moved }
        guard save(reminder, action: "edit") else {
            report("Couldn't save “\(item.title)”.")
            scheduleRefresh()
            return
        }
        if new.flagged != item.isFlagged, !ReminderKit.setFlagged(new.flagged, for: reminder, in: store) {
            report("Saved “\(new.title)”, but couldn't change its flag.")
        }
        scheduleRefresh()
    }

    // MARK: Sections

    /// Adds a section at the end of a real list.
    func addSection(named name: String, to list: ReminderList) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let calendar = calendar(withID: list.id) else { return }
        if !ReminderKit.addSection(named: name, to: calendar, in: store) { report("Couldn't add the section “\(name)”.") }
        scheduleRefresh()
    }

    func renameSection(_ id: String, in list: ReminderList, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let calendar = calendar(withID: list.id) else { return }
        if !ReminderKit.renameSection(id, in: calendar, to: name, in: store) { report("Couldn't rename the section.") }
        scheduleRefresh()
    }

    /// Removes a section. Its reminders stay in the list, without a section.
    func deleteSection(_ id: String, in list: ReminderList) {
        guard let calendar = calendar(withID: list.id) else { return }
        if !ReminderKit.deleteSection(id, in: calendar, in: store) { report("Couldn't delete the section.") }
        collapsedSectionIDs.remove(id)
        scheduleRefresh()
    }

    /// Puts a section at a new position among its list's sections. Sorting isn't touched, since it only
    /// applies inside each section.
    func moveSection(_ id: String, in list: ReminderList, toIndex index: Int) {
        guard let calendar = calendar(withID: list.id) else { return }
        var ids = ReminderKit.sections(of: calendar, in: store).map(\.id)
        guard let current = ids.firstIndex(of: id) else { return }
        ids.remove(at: current)
        ids.insert(id, at: min(max(index, 0), ids.count))
        if !ReminderKit.orderSections(ids, in: calendar, in: store) { report("Couldn't change the order of the sections.") }
        scheduleRefresh()
    }

    /// Moves a section up (-1) or down (+1) among its list's sections.
    func moveSection(_ id: String, in list: ReminderList, by offset: Int) {
        guard let calendar = calendar(withID: list.id) else { return }
        var ids = ReminderKit.sections(of: calendar, in: store).map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        if !ReminderKit.orderSections(ids, in: calendar, in: store) { report("Couldn't change the order of the sections.") }
        scheduleRefresh()
    }

    /// Puts a reminder into a section of its own list, or into none when `sectionID` is nil.
    func move(_ item: ReminderItem, toSection sectionID: String?) {
        // A sub-task follows its parent's section, so it has to leave the parent first.
        if item.parentID != nil, !detach(item) {
            report("Couldn't move “\(item.title)” to that section.")
            scheduleRefresh()
            return
        }
        guard let reminder = reminder(withID: item.id), let calendar = calendar(withID: item.listID) else {
            report("That reminder or list no longer exists.")
            scheduleRefresh()
            return
        }
        if !ReminderKit.move(reminder, toSection: sectionID, in: calendar, in: store) {
            report("Couldn't move “\(item.title)” to that section.")
        }
        // Sub-tasks stay with their parent.
        for child in openItems where child.parentID == item.id {
            if let stored = self.reminder(withID: child.id) { _ = ReminderKit.move(stored, toSection: sectionID, in: calendar, in: store) }
        }
        scheduleRefresh()
    }

    // MARK: Lists

    /// The colours offered for a new list.
    static let listColors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .systemPink, .systemBrown]

    /// Creates a list in the account new reminders normally go to.
    @discardableResult
    func createList(named name: String, color: NSColor) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else {
            report("There is no account to create the list in.")
            return false
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = name
        list.cgColor = color.cgColor
        list.source = source
        do { try store.saveCalendar(list, commit: true) } catch {
            log.error("Failed to create list: \(error.localizedDescription)")
            store.reset()
            report("Couldn't create the list “\(name)”.")
            return false
        }
        // A new list is shown right away, even when only some lists were chosen before.
        if var chosen = selectedListIDs {
            chosen.insert(list.calendarIdentifier)
            selectedListIDs = chosen
        }
        scheduleRefresh()
        return true
    }

    func renameList(_ list: ReminderList, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let calendar = calendar(withID: list.id), calendar.allowsContentModifications else { return }
        calendar.title = name
        do { try store.saveCalendar(calendar, commit: true) } catch {
            log.error("Failed to rename list: \(error.localizedDescription)")
            store.reset()
            report("Couldn't rename the list.")
        }
        scheduleRefresh()
    }

    /// Deletes a list with everything in it.
    func deleteList(_ list: ReminderList) {
        guard let calendar = calendar(withID: list.id), calendar.allowsContentModifications else {
            report("That list can't be deleted.")
            return
        }
        do { try store.removeCalendar(calendar, commit: true) } catch {
            log.error("Failed to delete list: \(error.localizedDescription)")
            store.reset()
            report("Couldn't delete the list “\(list.title)”.")
        }
        // Forget what was kept for the list.
        if preferredListID == list.id { preferredListID = nil }
        listSortOrders[list.id] = nil
        collapsedListIDs.remove(list.id)
        listOrder.removeAll { $0 == list.id }
        selectedListIDs?.remove(list.id)
        scheduleRefresh()
    }

    /// Whether a reminder has open sub-tasks of its own.
    func hasSubtasks(_ item: ReminderItem) -> Bool {
        openItems.contains { $0.parentID == item.id }
    }

    /// Makes a reminder a sub-task of another one in the same list.
    func makeSubtask(_ item: ReminderItem, of parent: ReminderItem) {
        guard item.listID == parent.listID, item.id != parent.id else { return }
        guard let child = reminder(withID: item.id), let parentReminder = reminder(withID: parent.id) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        if !ReminderKit.makeSubtask(child, of: parentReminder, in: store) {
            report("Couldn't make “\(item.title)” a sub-task of “\(parent.title)”.")
        }
        scheduleRefresh()
    }

    /// Sets or clears a reminder's due date.
    func setDue(_ item: ReminderItem, to date: Date?, hasTime: Bool) {
        change(item, "change the date of") { ReminderEditing.setDue(date, hasTime: hasTime, on: $0) }
    }

    /// Moves a reminder to another day, keeping its time of day.
    func setDay(_ item: ReminderItem, to day: Date) {
        let moved = ReminderEditing.moving(item.due, hasTime: item.dueHasTime, toDay: day)
        setDue(item, to: moved.date, hasTime: moved.hasTime)
    }

    /// Moves every late reminder among `items` to another day. One that has a time keeps it, unless that
    /// time has already gone by on the new day, in which case it only keeps the day.
    func rescheduleOverdue(in items: [ReminderItem], toDay day: Date) {
        let late = items.filter { isOverdue($0) }
        guard !late.isEmpty else { return }
        var failed = 0
        for item in late {
            guard let reminder = reminder(withID: item.id) else { failed += 1; continue }
            let moved = ReminderEditing.rescheduling(item.due, hasTime: item.dueHasTime, toDay: day)
            ReminderEditing.setDue(moved.date, hasTime: moved.hasTime, on: reminder)
            if !save(reminder, action: "reschedule") { failed += 1 }
        }
        if failed > 0 { report("Couldn't reschedule \(failed) of \(late.count) reminders.") }
        scheduleRefresh()
    }

    /// Sets a reminder's priority: 0 none, 1 high, 5 medium, 9 low.
    func setPriority(_ item: ReminderItem, to priority: Int) {
        change(item, "change the priority of") { $0.priority = priority }
    }

    /// Applies an edit to the stored reminder, saves it and reloads.
    private func change(_ item: ReminderItem, _ action: String, _ edit: (EKReminder) -> Void) {
        guard let reminder = reminder(withID: item.id) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        edit(reminder)
        if !save(reminder, action: action) { report("Couldn't \(action) “\(item.title)”.") }
        scheduleRefresh()
    }

    /// Flags or unflags a reminder.
    func setFlag(_ item: ReminderItem, to flagged: Bool) {
        guard let reminder = reminder(withID: item.id) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        if !ReminderKit.setFlagged(flagged, for: reminder, in: store) {
            report("Couldn't \(flagged ? "flag" : "unflag") “\(item.title)”.")
        }
        scheduleRefresh()
    }

    /// Permanently deletes a reminder.
    func delete(_ item: ReminderItem) {
        guard let reminder = reminder(withID: item.id) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        pendingRemovals[item.id] = Date()
        do { try store.remove(reminder, commit: true) } catch {
            log.error("Failed to delete reminder: \(error.localizedDescription)")
            pendingRemovals[item.id] = nil
            report("Couldn't delete “\(item.title)”.")
        }
        scheduleRefresh()
    }

    /// Opens the task's list in the Reminders app, or just the app if the list can't be opened directly.
    func openInReminders(_ item: ReminderItem) {
        guard let url = URL(string: "x-apple-reminderkit://REMCDList/\(item.listID)") else { return openRemindersApp() }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if error != nil { Task { @MainActor in self?.openRemindersApp() } }
        }
    }

    func openRemindersApp() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Completes a reminder without touching the task currently being timed.
    func completeOnly(_ item: ReminderItem) {
        Task { await complete(item) }
    }

    private func complete(_ item: ReminderItem) async {
        // Checking off a parent checks off its open sub-tasks too. A repeating task keeps its own state.
        let subtasks = item.isRepeating ? [] : openItems.filter { $0.parentID == item.id }
        // A repeating task isn't hidden: the same reminder stays and shows its next date after the refresh.
        if !item.isRepeating {
            // Hide it right away so a slow or stale refresh can't leave it in the list.
            let hidden = Set([item.id] + subtasks.map(\.id))
            for id in hidden { pendingRemovals[id] = Date() }
            sections = sections.compactMap { section in
                let rest = section.items.filter { !hidden.contains($0.id) }
                return rest.isEmpty ? nil : ReminderSection(list: section.list, items: rest)
            }
        }
        if let reminder = reminder(withID: item.id) {
            reminder.isCompleted = true
            if save(reminder, action: "complete") {
                var finished: [String] = []
                for subtask in subtasks {
                    let stored = self.reminder(withID: subtask.id)
                    stored?.isCompleted = true
                    if let stored, save(stored, action: "complete") {
                        finished.append(subtask.id)
                    } else {
                        pendingRemovals[subtask.id] = nil
                        report("Couldn't complete the sub-task “\(subtask.title)”.")
                    }
                }
                completedSubtasks[item.id] = finished.isEmpty ? nil : finished
                showCompletionBanner(for: item)
            } else {
                for subtask in subtasks { pendingRemovals[subtask.id] = nil }
                pendingRemovals[item.id] = nil
                report("Couldn't complete “\(item.title)”.")
            }
        } else {
            pendingRemovals[item.id] = nil
            report("That reminder no longer exists.")
        }
        await refresh()
    }

    // MARK: Undo

    private func showCompletionBanner(for item: ReminderItem) {
        var recent = item
        recent.depth = 0
        if !item.isRepeating {
            recentlyCompleted.removeAll { $0.id == item.id }
            recentlyCompleted.insert(recent, at: 0)
            recentlyCompleted = Array(recentlyCompleted.prefix(5))
        }
        undoBannerItem = recent
        undoBannerCanUndo = !item.isRepeating
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { self?.undoBannerItem = nil }
        }
    }

    /// Undoes the most recent completion. Repeating it steps back through the last five.
    func undoLast() {
        if let latest = recentlyCompleted.first { undoComplete(latest) }
    }

    /// Marks a recently completed task as not done again.
    func undoComplete(_ item: ReminderItem) {
        recentlyCompleted.removeAll { $0.id == item.id }
        if undoBannerItem?.id == item.id { undoBannerItem = nil }
        pendingRemovals[item.id] = nil
        if let reminder = reminder(withID: item.id) {
            reminder.isCompleted = false
            if !save(reminder, action: "undo") { report("Couldn't restore “\(item.title)”.") }
            // Sub-tasks that were checked off with it come back too.
            for id in completedSubtasks.removeValue(forKey: item.id) ?? [] {
                pendingRemovals[id] = nil
                if let subtask = self.reminder(withID: id) {
                    subtask.isCompleted = false
                    _ = save(subtask, action: "undo")
                }
            }
        } else {
            report("Couldn't restore “\(item.title)”. It no longer exists.")
        }
        scheduleRefresh()
    }

    // MARK: Focus timer

    func select(_ item: ReminderItem) {
        stopTicking()
        phase = .choosing(item)
    }

    func start(_ item: ReminderItem, minutes: Int) {
        runTotal = TimeInterval(max(1, minutes) * 60)
        now = Date()
        phase = .running(item, end: now.addingTimeInterval(runTotal))
        startTicking()
    }

    func cancel() {
        stopTicking()
        phase = .idle
    }

    func markDone(_ item: ReminderItem) {
        cancel()
        completeOnly(item)
    }

    private func startTicking() {
        tickLoop?.cancel()
        tickLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func stopTicking() {
        tickLoop?.cancel()
        tickLoop = nil
    }

    private func tick() {
        now = Date()
        guard case .running(let item, let end) = phase, now >= end else { return }
        stopTicking()
        phase = .finished(item)
        NSSound(named: "Glass")?.play()
    }

    // MARK: EventKit helpers

    private func reminder(withID id: String) -> EKReminder? {
        store.calendarItem(withIdentifier: id) as? EKReminder
    }

    private func calendar(withID id: String?) -> EKCalendar? {
        guard let id else { return nil }
        return store.calendars(for: .reminder).first { $0.calendarIdentifier == id }
    }

    private func report(_ message: String) {
        errorMessage = message
        errorExpiry?.cancel()
        errorExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self?.errorMessage = nil }
        }
    }

    func dismissError() {
        errorExpiry?.cancel()
        errorMessage = nil
    }

    private func save(_ reminder: EKReminder, action: String) -> Bool {
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            log.error("Failed to \(action) reminder: \(error.localizedDescription)")
            store.reset()   // drop the unsaved edit, so it doesn't linger on the object
            return false
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// "21:05" or "1:02:05".
func formatRemaining(_ interval: TimeInterval) -> String {
    let total = Int(interval.rounded(.up))
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

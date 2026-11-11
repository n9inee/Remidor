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

    /// How many reminders are due today or late, for the menu bar.
    var menuBarCount = 0
    /// Whether the menu bar shows that number next to its icon. On until turned off in Settings.
    var showMenuBarCount = UserDefaults.standard.object(forKey: DefaultsKey.showMenuBarCount) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showMenuBarCount, forKey: DefaultsKey.showMenuBarCount) }
    }

    /// Time left on a paused timer. Nil while it runs.
    var pausedRemaining: TimeInterval?
    var isPaused: Bool { pausedRemaining != nil }
    /// How long a break lasts, in minutes.
    static let breakMinutes = 5

    var remaining: TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        switch phase {
        case .running(_, let end), .onBreak(_, let end): return CountdownMath.remaining(until: end, now: now)
        default: return 0
        }
    }

    // MARK: Undo state

    /// The last few completed tasks, newest first.
    var recentlyCompleted: [ReminderItem] = []
    /// The latest completion, shown in a banner for a few seconds.
    var undoBannerItem: ReminderItem?
    /// When that banner appeared, to tell whether an edit came before or after it.
    var completionBannerAt = Date.distantPast
    /// False for repeating tasks. Reminders keeps the original, moves it to its next date and logs a
    /// separate completed copy, so there is nothing safe to un-complete.
    var undoBannerCanUndo = true
    /// The latest edit or deletion, shown in a banner with an Undo for a few seconds.
    var undoNotice: UndoNotice?
    /// How long an edit or deletion can be undone, in seconds.
    static let undoWindow = 5

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
    var weekStart: Int = TaskModel.savedWeekday(DefaultsKey.weekStart, default: 2) {
        didSet { UserDefaults.standard.set(weekStart, forKey: DefaultsKey.weekStart) }
    }

    var weekendStart: Int = TaskModel.savedWeekday(DefaultsKey.weekendStart, default: 7) {
        didSet { UserDefaults.standard.set(weekendStart, forKey: DefaultsKey.weekendStart) }
    }

    /// How a typed date like 5.10. is read.
    var dateOrder = DateOrder(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.dateOrder) ?? "") ?? .systemDefault {
        didSet { UserDefaults.standard.set(dateOrder.rawValue, forKey: DefaultsKey.dateOrder) }
    }

    /// A saved weekday, or the default when nothing valid was saved (1 is Sunday ... 7 is Saturday).
    private static func savedWeekday(_ key: String, default fallback: Int) -> Int {
        let saved = UserDefaults.standard.integer(forKey: key)
        return (1...7).contains(saved) ? saved : fallback
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
    @ObservationIgnored private var undoStack = UndoStack()
    @ObservationIgnored private var noticeTimers: [UUID: Task<Void, Never>] = [:]
    /// Reminders deleted by the user that are only hidden for now, so the deletion can still be undone. They are
    /// removed from Reminders when the undo window ends, or when the app quits. Keyed by the deleted reminder's id.
    @ObservationIgnored private var deferredDeletes = DeferredDeletes()
    @ObservationIgnored private var deleteTimers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var errorExpiry: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var tickLoop: Task<Void, Never>?

    init() {
        // A deletion still waiting out its undo window must not be lost when the app quits.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushDeletes() }
        }
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
        let hidden = deferredDeletes.hiddenIDs
        let visible = items.filter { pendingRemovals[$0.id] == nil && !hidden.contains($0.id) }

        allTags = Self.knownTags(in: items)
        sections = makeSections(from: visible, listSections: sectionLookups.mapValues(\.allSections))
        menuBarCount = Self.dueCount(in: visible, before: ReminderEditing.startOfTomorrow())
        endTimerIfTaskIsGone()
    }

    /// How many open reminders are due today or late, which is what the Today list holds.
    nonisolated static func dueCount(in items: [ReminderItem], before end: Date) -> Int {
        items.filter { ($0.due ?? .distantFuture) < end }.count
    }

    /// The task a timer is set up or running for, if any.
    private var timerItem: ReminderItem? {
        switch phase {
        case .idle: nil
        case .choosing(let item), .running(let item, _), .finished(let item), .onBreak(let item, _): item
        }
    }

    /// Stops the timer when its task was checked off or deleted somewhere else, instead of leaving a countdown for
    /// something that no longer exists.
    private func endTimerIfTaskIsGone() {
        guard let item = timerItem else { return }
        if !deferredDeletes.hiddenIDs.contains(item.id), let stored = reminder(withID: item.id), !stored.isCompleted { return }
        cancel()
        report("“\(item.title)” was checked off or deleted, so its timer stopped.")
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

    /// Everything that is late, then whole days of what is coming.
    private func nextUpItems(from items: [ReminderItem]) -> [ReminderItem] {
        items.nextUp(minimum: SmartList.nextUpCount)
    }

    private func makeSections(from items: [ReminderItem], listSections: [String: [ReminderKit.ListSection]]) -> [ReminderSection] {
        let endOfToday = ReminderEditing.startOfTomorrow()
        let byList = Dictionary(grouping: items, by: \.listID)

        return lists.filter(isSelected).compactMap { list in
            var matching: [ReminderItem] = switch list.id {
            case SmartList.today.id: items.filter { ($0.due ?? .distantFuture) < endOfToday }
            case SmartList.nextUp.id: nextUpItems(from: items)
            case SmartList.scheduled.id: items.filter { $0.due != nil }
            case SmartList.flagged.id: items.filter(\.isFlagged)
            case SmartList.all.id: items
            default: byList[list.id] ?? []
            }
            // A smart list shows the sub-tasks of what it lists, dated or not, so checking off a parent never
            // takes along work that can't be seen.
            if list.isSmart, list.id != SmartList.all.id { matching = withSubtasks(matching, from: items) }
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

    /// The reminders with the sub-tasks of theirs that aren't among them.
    private func withSubtasks(_ listed: [ReminderItem], from items: [ReminderItem]) -> [ReminderItem] {
        let ids = Set(listed.map(\.id))
        return listed + items.filter { !ids.contains($0.id) && ($0.parentID.map(ids.contains) ?? false) }
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

    // MARK: Searching and the keyboard

    /// The lists as shown while searching: only what matches. Without a search, all of them.
    func displayedSections(matching query: String) -> [ReminderSection] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? sections : sections.compactMap { $0.filtered(by: query) }
    }

    /// The keys of the reminders in the order the dropdown shows them, for moving through them with the arrow keys.
    /// Folded lists, sections and sub-tasks are skipped, except while searching.
    func rowKeys(matching query: String) -> [String] {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return displayedSections(matching: query).flatMap { section -> [String] in
            guard searching || !collapsedListIDs.contains(section.id) else { return [] }
            let entries = section.entries(foldedParents: searching ? [] : collapsedParentIDs,
                                          foldedSections: searching ? [] : collapsedSectionIDs)
            return entries.compactMap { entry in
                if case .item(let item) = entry { section.key(for: item) } else { nil }
            }
        }
    }

    func item(forRowKey key: String) -> ReminderItem? {
        sections.lazy.compactMap { section in section.items.first { section.key(for: $0) == key } }.first
    }

    /// What was typed in the hotkey box when it closed, kept for a while so Esc or a stray click doesn't lose it.
    @ObservationIgnored private var panelDraft: QuickAddDraft?
    @ObservationIgnored var panelClosedAt: Date?

    /// The draft for the hotkey box: the unfinished one from a moment ago, or a new one.
    func draftForPanel(now: Date = Date()) -> QuickAddDraft {
        if let panelDraft, panelDraft.hasText, let closed = panelClosedAt, now.timeIntervalSince(closed) < 600 { return panelDraft }
        let fresh = QuickAddDraft(model: self)
        panelDraft = fresh
        return fresh
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
        reminder.notes = new.notes
        reminder.url = new.url
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
        guard save(reminder, action: "move") else {
            report("Couldn't move “\(item.title)”.")
            scheduleRefresh()
            return
        }
        // Sub-tasks go along with their parent.
        var stuck = 0
        for child in openItems where child.parentID == item.id {
            guard let stored = self.reminder(withID: child.id) else { stuck += 1; continue }
            stored.calendar = target
            if !save(stored, action: "move") { stuck += 1 }
        }
        if stuck > 0 { report("Moved “\(item.title)”, but \(stuck) of its sub-tasks stayed behind.") }
        scheduleRefresh()
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

    /// Saves what was edited in place: title, notes, link, date, priority, flag and list.
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
        if new.notes != item.notes { reminder.notes = new.notes }
        if new.url != item.url { reminder.url = new.url }
        // Only touched when it was changed, so a repeat Remidor can't describe stays as it is.
        if new.recurrence != item.recurrence {
            for rule in reminder.recurrenceRules ?? [] { reminder.removeRecurrenceRule(rule) }
            if let recurrence = new.recurrence { reminder.addRecurrenceRule(recurrence.makeRule()) }
        }
        guard save(reminder, action: "edit") else {
            report("Couldn't save “\(item.title)”.")
            scheduleRefresh()
            return
        }
        if new.flagged != item.isFlagged, !ReminderKit.setFlagged(new.flagged, for: reminder, in: store) {
            report("Saved “\(new.title)”, but couldn't change its flag.")
        }
        // Moving to another list takes its sub-tasks along, or lets a sub-task go, so it is done the way the List menu does it.
        if let listID = new.listID, listID != item.listID { move(item, toListID: listID) }
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
        guard !name.isEmpty, let calendar = calendar(withID: list.id) else { return }
        guard calendar.allowsContentModifications else {
            report("“\(list.title)” can't be renamed.")
            return
        }
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
            scheduleRefresh()
            return
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

    /// How many open sub-tasks a reminder has, shown or not.
    func subtaskCount(of item: ReminderItem) -> Int {
        openItems.filter { $0.parentID == item.id }.count
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
        let (oldDue, oldHasTime) = (item.due, item.dueHasTime)
        guard change(item, "change the date of", { ReminderEditing.setDue(date, hasTime: hasTime, on: $0) }) else { return }
        postNotice(date == nil ? "Removed the date of “\(item.title)”" : "Rescheduled “\(item.title)”", icon: "calendar") { [weak self] in
            self?.change(item, "restore the date of") { ReminderEditing.setDue(oldDue, hasTime: oldHasTime, on: $0) }
        }
    }

    /// Moves a reminder to another day, keeping its time of day, unless that time has already gone by on the new
    /// day: then it only gets the day, so it isn't late the moment it is moved.
    func setDay(_ item: ReminderItem, to day: Date) {
        let moved = ReminderEditing.rescheduling(item.due, hasTime: item.dueHasTime, toDay: day)
        setDue(item, to: moved.date, hasTime: moved.hasTime)
    }

    /// Moves every late reminder among `items` to another day. One that has a time keeps it, unless that
    /// time has already gone by on the new day, in which case it only keeps the day.
    func rescheduleOverdue(in items: [ReminderItem], toDay day: Date) {
        let late = items.filter { isOverdue($0) }
        guard !late.isEmpty else { return }
        var failed = 0
        var moved: [ReminderItem] = []
        for item in late {
            guard let reminder = reminder(withID: item.id) else { failed += 1; continue }
            let new = ReminderEditing.rescheduling(item.due, hasTime: item.dueHasTime, toDay: day)
            ReminderEditing.setDue(new.date, hasTime: new.hasTime, on: reminder)
            if save(reminder, action: "reschedule") { moved.append(item) } else { failed += 1 }
        }
        if failed > 0 { report("Couldn't reschedule \(failed) of \(late.count) reminders.") }
        if !moved.isEmpty {
            let what = moved.count == 1 ? "“\(moved[0].title)”" : "\(moved.count) reminders"
            postNotice("Rescheduled \(what)", icon: "calendar") { [weak self] in
                guard let self else { return }
                var failed = 0
                for old in moved {
                    guard let reminder = self.reminder(withID: old.id) else { failed += 1; continue }
                    ReminderEditing.setDue(old.due, hasTime: old.dueHasTime, on: reminder)
                    if !self.save(reminder, action: "restore") { failed += 1 }
                }
                if failed > 0 { self.report("Couldn't restore \(failed) of \(moved.count) reminders.") }
                self.scheduleRefresh()
            }
        }
        scheduleRefresh()
    }

    /// Replaces a reminder's notes. Empty text clears them.
    func setNotes(_ item: ReminderItem, to notes: String) {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard trimmed != item.notes else { return }
        change(item, "change the notes of") { $0.notes = trimmed }
    }

    /// Sets a reminder's priority: 0 none, 1 high, 5 medium, 9 low.
    func setPriority(_ item: ReminderItem, to priority: Int) {
        let old = item.priority
        guard change(item, "change the priority of", { $0.priority = priority }) else { return }
        postNotice("Changed the priority of “\(item.title)”", icon: "exclamationmark") { [weak self] in
            self?.change(item, "restore the priority of") { $0.priority = old }
        }
    }

    /// Applies an edit to the stored reminder, saves it and reloads.
    @discardableResult
    private func change(_ item: ReminderItem, _ action: String, _ edit: (EKReminder) -> Void) -> Bool {
        guard let reminder = reminder(withID: item.id) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return false
        }
        edit(reminder)
        let saved = save(reminder, action: action)
        if !saved { report("Couldn't \(action) “\(item.title)”.") }
        scheduleRefresh()
        return saved
    }

    /// Shows "message  Undo" for a few seconds. Several can wait at once: the banner shows the newest, and
    /// when that one is undone or runs out the one before it comes back.
    private func postNotice(_ message: String, icon: String, undo: @escaping () -> Void) {
        let notice = UndoNotice(message: message, icon: icon)
        undoStack.push(notice, undo: undo)
        undoNotice = undoStack.newest
        noticeTimers[notice.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            if !Task.isCancelled { self?.expireNotice(notice.id) }
        }
    }

    private func expireNotice(_ id: UUID) {
        noticeTimers[id] = nil
        undoStack.remove(id: id)
        undoNotice = undoStack.newest
    }

    /// Takes back the newest edit or deletion that can still be undone.
    func undoNoticeAction() {
        guard let entry = undoStack.popNewest() else { return }
        noticeTimers.removeValue(forKey: entry.notice.id)?.cancel()
        undoNotice = undoStack.newest
        entry.undo()
    }

    /// The edit banner, unless a task was checked off since: then its banner is the one shown.
    var shownNotice: UndoNotice? {
        guard let notice = undoNotice else { return nil }
        return undoBannerItem == nil || notice.created > completionBannerAt ? notice : nil
    }

    /// The completion banner, unless an edit came after it.
    var shownCompletion: ReminderItem? {
        shownNotice == nil ? undoBannerItem : nil
    }

    /// Whether ⌘Z has something to take back. A repeating task that was just checked off can't be undone, and
    /// then ⌘Z must not reach back to an older one.
    var canUndoLast: Bool {
        if let notice = undoNotice, notice.created > completionBannerAt { return true }
        return !recentlyCompleted.isEmpty && !(undoBannerItem != nil && !undoBannerCanUndo)
    }

    /// Flags or unflags a reminder.
    func setFlag(_ item: ReminderItem, to flagged: Bool) {
        guard let reminder = reminder(withID: item.id) else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        let was = item.isFlagged
        if ReminderKit.setFlagged(flagged, for: reminder, in: store) {
            postNotice(flagged ? "Flagged “\(item.title)”" : "Removed the flag from “\(item.title)”", icon: "flag") { [weak self] in
                guard let self else { return }
                if let stored = self.reminder(withID: item.id), !ReminderKit.setFlagged(was, for: stored, in: self.store) {
                    self.report("Couldn't restore the flag of “\(item.title)”.")
                }
                self.scheduleRefresh()
            }
        } else {
            report("Couldn't \(flagged ? "flag" : "unflag") “\(item.title)”.")
        }
        scheduleRefresh()
    }

    /// Deletes a reminder and its sub-tasks. They are hidden at once but only removed from Reminders when the undo
    /// window ends, because Reminders can't bring a deleted reminder back: until then Undo just shows them again.
    func delete(_ item: ReminderItem) {
        guard reminder(withID: item.id) != nil else {
            report("That reminder no longer exists.")
            scheduleRefresh()
            return
        }
        let subtasks = openItems.filter { $0.parentID == item.id }.map(\.id)
        deferredDeletes.hold(root: item.id, subtasks: subtasks, title: item.title)
        let gone = Set([item.id] + subtasks)
        sections = sections.compactMap { section in
            let rest = section.items.filter { !gone.contains($0.id) }
            return rest.isEmpty ? nil : ReminderSection(list: section.list, items: rest)
        }
        deleteTimers[item.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            if !Task.isCancelled { self?.commitDelete(of: item.id) }
        }
        postNotice("Deleted “\(item.title)”", icon: "trash") { [weak self] in
            guard let self, self.deferredDeletes.undo(root: item.id) != nil else { return }
            self.deleteTimers.removeValue(forKey: item.id)?.cancel()
            self.scheduleRefresh()
        }
        scheduleRefresh()
    }

    /// Removes a hidden reminder and its sub-tasks from Reminders for good.
    private func commitDelete(of id: String) {
        deleteTimers.removeValue(forKey: id)?.cancel()
        guard let batch = deferredDeletes.release(root: id) else { return }
        carryOut(batch, root: id)
        scheduleRefresh()
    }

    private func carryOut(_ batch: DeferredDeletes.Batch, root id: String) {
        // Hidden as removed until a fetch confirms it, so a stale fetch can't bring them back.
        for id in batch.ids { pendingRemovals[id] = Date() }
        do {
            // Sub-tasks first, then the parent.
            for subId in batch.ids.dropFirst() {
                if let stored = reminder(withID: subId) { try store.remove(stored, commit: false) }
            }
            if let stored = reminder(withID: id) { try store.remove(stored, commit: false) }
            try store.commit()
        } catch {
            log.error("Failed to delete reminder: \(error.localizedDescription)")
            store.reset()
            for id in batch.ids { pendingRemovals[id] = nil }
            report("Couldn't delete “\(batch.title)”.")
        }
    }

    /// Carries out every deletion still waiting, for when the app quits.
    private func flushDeletes() {
        for timer in deleteTimers.values { timer.cancel() }
        deleteTimers.removeAll()
        for (root, batch) in deferredDeletes.releaseAll() { carryOut(batch, root: root) }
    }

    /// Opens the reminder itself in the Reminders app, which shows its list with it selected. If that can't be
    /// opened it tries the list, and then just the app.
    func openInReminders(_ item: ReminderItem) {
        let links = ["REMCDReminder/\(item.id)", "REMCDList/\(item.listID)"].compactMap { URL(string: "x-apple-reminderkit://" + $0) }
        open(links[...])
    }

    private func open(_ links: ArraySlice<URL>) {
        guard let url = links.first else { return openRemindersApp() }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if error != nil { Task { @MainActor in self?.open(links.dropFirst()) } }
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
        completionBannerAt = Date()
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
        if let notice = undoNotice, notice.created > completionBannerAt { return undoNoticeAction() }
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
                    if !save(subtask, action: "undo") { report("Couldn't restore the sub-task “\(subtask.title ?? "Untitled")”.") }
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
        pausedRemaining = nil
        phase = .choosing(item)
    }

    func start(_ item: ReminderItem, minutes: Int) {
        runTotal = TimeInterval(max(1, minutes) * 60)
        TimerNotice.askPermission()
        now = Date()
        pausedRemaining = nil
        phase = .running(item, end: now.addingTimeInterval(runTotal))
        startTicking()
    }

    /// Freezes the countdown. The time left is kept until `resume`.
    func pause() {
        guard case .running(_, let end) = phase, pausedRemaining == nil else { return }
        now = Date()
        pausedRemaining = CountdownMath.remaining(until: end, now: now)
        stopTicking()
    }

    /// Carries on from where `pause` stopped.
    func resume() {
        guard case .running(let item, _) = phase, let left = pausedRemaining else { return }
        now = Date()
        pausedRemaining = nil
        phase = .running(item, end: CountdownMath.end(after: left, from: now))
        startTicking()
    }

    /// Rests for a few minutes after a session. When the break is over the task is up for another one.
    func startBreak(after item: ReminderItem) {
        runTotal = TimeInterval(Self.breakMinutes * 60)
        TimerNotice.askPermission()
        now = Date()
        pausedRemaining = nil
        phase = .onBreak(item, end: now.addingTimeInterval(runTotal))
        startTicking()
    }

    /// Ends a break early and goes back to setting up the next session.
    func endBreak() {
        guard case .onBreak(let item, _) = phase else { return }
        stopTicking()
        phase = .choosing(item)
    }

    func cancel() {
        stopTicking()
        pausedRemaining = nil
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
        switch phase {
        case .running(let item, let end) where CountdownMath.isFinished(end: end, now: now):
            stopTicking()
            phase = .finished(item)
            NSSound(named: "Glass")?.play()
            TimerNotice.post(for: item)
        case .onBreak(let item, let end) where CountdownMath.isFinished(end: end, now: now):
            stopTicking()
            phase = .choosing(item)
            NSSound(named: "Glass")?.play()
            TimerNotice.postBreakOver(for: item)
        default:
            break
        }
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

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// "21:05" or "1:02:05".
func formatRemaining(_ interval: TimeInterval) -> String {
    let total = Int(interval.rounded(.up))
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

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

    // MARK: Focus timer

    var phase: Phase = .idle
    var now = Date()
    var runTotal: TimeInterval = 1

    var remaining: TimeInterval {
        if case .running(_, let end) = phase { return max(0, end.timeIntervalSince(now)) }
        return 0
    }

    // MARK: Undo

    /// The last few completed tasks, newest first.
    var recentlyCompleted: [ReminderItem] = []
    /// The latest completion, offered for undo in a banner for a few seconds.
    var undoBannerItem: ReminderItem?

    // MARK: Settings (saved between launches)

    var defaultMinutes: Int = {
        let saved = UserDefaults.standard.integer(forKey: DefaultsKey.defaultMinutes)
        return saved > 0 ? saved : 30
    }() {
        didSet { UserDefaults.standard.set(defaultMinutes, forKey: DefaultsKey.defaultMinutes) }
    }

    var sortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.sortOrder) ?? "") ?? .dueDate {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKey.sortOrder)
            scheduleRefresh()
        }
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
    /// Reminders just completed or deleted. They stay hidden until a fetch confirms the change,
    /// so a stale fetch can't bring them back.
    @ObservationIgnored private var pendingRemovals = [String: Date]()
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?
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

    func refresh() async {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        hasAccess = true
        accessDenied = false

        store.refreshSourcesIfNecessary()
        let calendars = store.calendars(for: .reminder)
        updateLists(from: calendars)

        let items = await fetchIncomplete(in: calendars)

        // Drop a pending removal once a fetch no longer returns the reminder, or after 10 seconds.
        let fetchedIDs = Set(items.map(\.id))
        pendingRemovals = pendingRemovals.filter { fetchedIDs.contains($0.key) && Date().timeIntervalSince($0.value) < 10 }
        let visible = items.filter { pendingRemovals[$0.id] == nil }

        allTags = Self.knownTags(in: items)
        sections = makeSections(from: visible)
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

    private func fetchIncomplete(in calendars: [EKCalendar]) async -> [ReminderItem] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let all = reminders ?? []
                continuation.resume(returning: all.map { r in
                    ReminderItem(
                        id: r.calendarItemIdentifier,
                        title: r.title ?? "Untitled",
                        listID: r.calendar.calendarIdentifier,
                        listTitle: r.calendar.title,
                        listColor: Color(cgColor: r.calendar.cgColor),
                        due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        dueHasTime: r.dueDateComponents?.hour != nil,
                        priority: r.priority,
                        created: r.creationDate,
                        notes: r.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        url: r.url,
                        tags: ReminderKit.tags(of: r),
                        parentID: ReminderKit.parentIdentifier(of: r, among: all)
                    )
                })
            }
        }
    }

    private func makeSections(from items: [ReminderItem]) -> [ReminderSection] {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        let byList = Dictionary(grouping: items, by: \.listID)

        return lists.filter(isSelected).compactMap { list in
            let matching: [ReminderItem] = switch list.id {
            case SmartList.today.id: items.filter { ($0.due ?? .distantFuture) < endOfToday }
            case SmartList.scheduled.id: items.filter { $0.due != nil }
            case SmartList.all.id: items
            default: byList[list.id] ?? []
            }
            guard !matching.isEmpty else { return nil }
            let ordered = SmartList.sortsByTime(list) ? matching.sortedByDueTime() : matching.sorted(by: sortOrder)
            return ReminderSection(list: list, items: ordered.nestingSubtasks())
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

    // MARK: Changing reminders

    func addReminder(_ new: NewReminder) async -> Bool {
        guard let calendar = calendar(withID: new.listID) ?? calendar(withID: defaultListID) ?? store.defaultCalendarForNewReminders() else {
            return false
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = new.title
        reminder.priority = new.priority ?? 0
        if let due = new.due {
            let parts: Set<Calendar.Component> = new.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(parts, from: due)
            if new.hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        guard save(reminder, action: "add") else { return false }
        await refresh()
        return true
    }

    /// Moves a reminder to another list.
    func move(_ item: ReminderItem, toListID id: String) {
        guard item.listID != id, let reminder = reminder(withID: item.id), let target = calendar(withID: id) else { return }
        reminder.calendar = target
        _ = save(reminder, action: "move")
        scheduleRefresh()
    }

    /// Permanently deletes a reminder.
    func delete(_ item: ReminderItem) {
        guard let reminder = reminder(withID: item.id) else { return }
        pendingRemovals[item.id] = Date()
        do { try store.remove(reminder, commit: true) } catch {
            log.error("Failed to delete reminder: \(error.localizedDescription)")
            pendingRemovals[item.id] = nil
        }
        scheduleRefresh()
    }

    /// Opens the task's list in the Reminders app, or just the app if the list can't be opened directly.
    func openInReminders(_ item: ReminderItem) {
        @MainActor func openApp() {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
        guard let url = URL(string: "x-apple-reminderkit://REMCDList/\(item.listID)") else { return openApp() }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { Task { @MainActor in openApp() } }
        }
    }

    /// Completes a reminder without touching the task currently being timed.
    func completeOnly(_ item: ReminderItem) {
        Task { await complete(item) }
    }

    private func complete(_ item: ReminderItem) async {
        // Hide it right away so a slow or stale refresh can't leave it in the list.
        pendingRemovals[item.id] = Date()
        sections = sections.compactMap { section in
            let rest = section.items.filter { $0.id != item.id }
            return rest.isEmpty ? nil : ReminderSection(list: section.list, items: rest)
        }
        if let reminder = reminder(withID: item.id) {
            reminder.isCompleted = true
            if save(reminder, action: "complete") { offerUndo(for: item) } else { pendingRemovals[item.id] = nil }
        } else {
            pendingRemovals[item.id] = nil
        }
        await refresh()
    }

    // MARK: Undo

    private func offerUndo(for item: ReminderItem) {
        var recent = item
        recent.depth = 0
        recentlyCompleted.removeAll { $0.id == item.id }
        recentlyCompleted.insert(recent, at: 0)
        recentlyCompleted = Array(recentlyCompleted.prefix(5))

        undoBannerItem = recent
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { self?.undoBannerItem = nil }
        }
    }

    /// Marks a recently completed task as not done again.
    func undoComplete(_ item: ReminderItem) {
        recentlyCompleted.removeAll { $0.id == item.id }
        if undoBannerItem?.id == item.id { undoBannerItem = nil }
        pendingRemovals[item.id] = nil
        if let reminder = reminder(withID: item.id) {
            reminder.isCompleted = false
            _ = save(reminder, action: "undo")
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

    private func save(_ reminder: EKReminder, action: String) -> Bool {
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            log.error("Failed to \(action) reminder: \(error.localizedDescription)")
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

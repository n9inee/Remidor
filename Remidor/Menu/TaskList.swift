//
//  TaskList.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import SwiftUI

/// The scrolling list of reminders, one section per list. It is exactly as tall as its content, up to
/// a limit you set by dragging the handle under it.
struct TaskList: View {
    let model: TaskModel
    let onStart: (ReminderItem) -> Void

    @AppStorage(DefaultsKey.dropdownMaxHeight) private var maxHeight = defaultMaxHeight
    @State private var contentHeight: CGFloat?
    @State private var dragStartHeight: Double?
    @State private var gripHovering = false
    @State private var drag: TaskDrag?
    @State private var scrollHandle = ScrollHandle()
    @State private var dragLoop: Task<Void, Never>?
    @State private var frames = RowFrames()
    @State private var justDragged = false

    private static let defaultMaxHeight = 320.0
    private static let minimumHeight = 120.0

    var body: some View {
        if model.accessDenied {
            VStack(alignment: .leading, spacing: 8) {
                Label("Remidor needs access to your reminders.", systemImage: "lock.fill")
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } else if model.sections.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    sections
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                        .background(ThinScrollers(handle: scrollHandle))
                }
                .frame(height: visibleHeight)
                .animation(.snappy(duration: 0.4), value: visibleHeight)

                if (contentHeight ?? 0) > Self.minimumHeight { resizeHandle }
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 { Divider().padding(.vertical, 6) }
                let collapsed = model.collapsedListIDs.contains(section.id)
                SectionHeader(section: section, collapsed: collapsed) {
                    withAnimation(.snappy(duration: 0.4)) { model.toggleCollapsed(section.list) }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames.headers[section.id] = $0 }
                if !collapsed {
                    let items = section.items.hidingFoldedSubtasks(model.collapsedParentIDs)
                    ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                        let foldedSection = item.sectionID.map(model.collapsedSectionIDs.contains) ?? false
                        // The name of a list section, like "Food", shows once above its first reminder.
                        if let title = item.sectionTitle, let id = item.sectionID,
                           position == 0 || items[position - 1].sectionID != id {
                            SubheadingRow(title: title, count: items.filter { $0.sectionID == id }.count, folded: foldedSection) {
                                withAnimation(.snappy(duration: 0.4)) { model.toggleSection(id) }
                            }
                        }
                        if !foldedSection {
                            let carried = drag?.item.id == item.id && drag?.sectionID == section.id
                            TaskRow(item: item, model: model, start: { if !justDragged { onStart(item) } }, done: { model.completeOnly(item) })
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames.rows[section.id + "|" + item.id] = $0 }
                                .onDisappear { frames.rows[section.id + "|" + item.id] = nil }
                                .background(RoundedRectangle(cornerRadius: 7).fill(.regularMaterial).opacity(carried ? 1 : 0))
                                .scaleEffect(carried ? 1.03 : 1)
                                .shadow(color: .black.opacity(carried ? 0.4 : 0), radius: carried ? 12 : 0, y: carried ? 6 : 0)
                                .offset(carried ? drag?.translation ?? .zero : .zero)
                                .zIndex(carried ? 10 : 0)
                                .simultaneousGesture(dragGesture(item, in: section))
                                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                        removal: .opacity.combined(with: .scale(scale: 0.95))))
                        }
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.5), value: layoutKey)
        .animation(.snappy(duration: 0.4), value: model.collapsedParentIDs)
        .animation(.snappy(duration: 0.4), value: model.collapsedSectionIDs)
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) { dropIndicator }
    }

    // MARK: Dragging

    private static let space = "taskList"

    /// Picking a reminder up and carrying it. The row follows the mouse; what is under it lights up.
    private func dragGesture(_ item: ReminderItem, in section: ReminderSection) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard item.depth == 0 else { return }
                if drag == nil {
                    // The mouse has already moved a few points; the row starts from where it was pressed.
                    guard let pointer = scrollHandle.pointer else { return }
                    let start = CGPoint(x: pointer.x - value.translation.width, y: pointer.y - value.translation.height)
                    drag = TaskDrag(item: item, sectionID: section.id, start: start, location: pointer)
                    dragLoop = Task { @MainActor in
                        while !Task.isCancelled {
                            followMouse()
                            try? await Task.sleep(for: .milliseconds(16))
                        }
                    }
                }
                followMouse()
            }
            .onEnded { _ in finishDrag() }
    }

    /// Moves the carried row to the mouse and scrolls the list when it is near the top or bottom edge.
    private func followMouse() {
        guard var current = drag, let pointer = scrollHandle.pointer else { return }
        // The mouse button was let go somewhere the gesture didn't hear about.
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return finishDrag() }
        let height = scrollHandle.viewportHeight
        let zone: CGFloat = 40
        let fromTop = pointer.y - scrollHandle.offset
        let fromBottom = scrollHandle.offset + height - pointer.y
        if fromTop < zone { scrollHandle.scroll(by: -scrollSpeed(zone - fromTop, zone)) }
        else if fromBottom < zone { scrollHandle.scroll(by: scrollSpeed(zone - fromBottom, zone)) }
        // Read again, since scrolling moves what is under the mouse.
        current.location = scrollHandle.pointer ?? pointer
        if current.location != drag?.location { drag = current }
    }

    /// Faster the closer the mouse is to the edge, from a crawl up to about 16 points per frame.
    private func scrollSpeed(_ depth: CGFloat, _ zone: CGFloat) -> CGFloat {
        3 + min(max(depth / zone, 0), 1.2) * 13
    }

    private func finishDrag() {
        dragLoop?.cancel()
        dragLoop = nil
        guard let finished = drag else { return }
        let target = dropTarget(for: finished)
        withAnimation(.snappy(duration: 0.35)) { drag = nil }
        justDragged = true
        Task { try? await Task.sleep(for: .seconds(0.3)); justDragged = false }
        if let target { perform(target.action, for: finished.item) }
    }

    private func perform(_ action: DropAction, for item: ReminderItem) {
        switch action {
        case .reorder(let target, let after): model.reorder(item, nextTo: target, after: after)
        case .move(let list): model.move(item, toListID: list.id)
        case .flag: model.setFlag(item, to: true)
        case .today: model.setDay(item, to: Date())
        case .subtask(let parent): model.makeSubtask(item, of: parent)
        }
    }

    /// What dropping here would do, and where to show it.
    private struct DropTarget {
        let action: DropAction
        let rect: CGRect
    }

    private func dropTarget(for drag: TaskDrag) -> DropTarget? {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        let moving = drag.item

        /// `fraction` is how far down the row the mouse is: the edges place the reminder before or after it,
        /// the middle makes it a sub-task.
        func action(on list: ReminderList, row target: ReminderItem?, fraction: CGFloat = 0.5) -> DropAction? {
            if list.isSmart {
                if list.id == SmartList.flagged.id { return moving.isFlagged ? nil : .flag }
                if list.id == SmartList.today.id { return (moving.due ?? .distantFuture) < endOfToday ? nil : .today }
                return nil   // Scheduled and All take nothing
            }
            if moving.listID != list.id { return .move(list) }
            guard let target, moving.depth == 0, target.depth == 0, moving.id != target.id,
                  moving.sectionID == target.sectionID else { return nil }
            if (0.28...0.72).contains(fraction), !model.hasSubtasks(moving) { return .subtask(of: target) }
            return .reorder(target: target, after: fraction >= 0.5)
        }

        for section in model.sections {
            if let rect = frames.headers[section.id], rect.contains(drag.location) {
                return action(on: section.list, row: nil).map { DropTarget(action: $0, rect: rect) }
            }
            guard !model.collapsedListIDs.contains(section.id) else { continue }
            let items = section.items.hidingFoldedSubtasks(model.collapsedParentIDs)
            for item in items where !(item.sectionID.map(model.collapsedSectionIDs.contains) ?? false) {
                guard let rect = frames.rows[section.id + "|" + item.id], rect.contains(drag.location) else { continue }
                let fraction = rect.height > 0 ? (drag.location.y - rect.minY) / rect.height : 0.5
                guard let result = action(on: section.list, row: item, fraction: fraction) else { return nil }
                switch result {
                case .reorder, .subtask:
                    return DropTarget(action: result, rect: rect)
                default:
                    // Moving to a list, flagging and Today belong to the list, so its name lights up, not the reminder.
                    return DropTarget(action: result, rect: frames.headers[section.id] ?? rect)
                }
            }
        }
        return nil
    }

    @ViewBuilder private var dropIndicator: some View {
        if let drag, let target = dropTarget(for: drag) {
            let rect = target.rect
            if case .reorder(_, let after) = target.action {
                Capsule().fill(Color.accentColor)
                    .frame(width: max(rect.width - 12, 0), height: 3)
                    .offset(x: rect.minX + 6, y: (after ? rect.maxY : rect.minY) - 1.5)
            } else {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 2)
                    .overlay(alignment: .trailing) {
                        Text(target.action.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                            .padding(.trailing, 30)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.hasAccess ? "sparkles" : "hourglass")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .speed(0.5), isActive: !model.hasAccess)
            Text(model.hasAccess ? "All clear" : "Loading…").font(.headline)
            if model.hasAccess {
                Text("No open reminders in the selected lists.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
    }

    // MARK: Height

    /// The list never grows past the screen, however far the handle was dragged.
    private var screenLimit: Double {
        max(240, (NSScreen.main?.visibleFrame.height ?? 900) - 300)
    }

    /// As tall as the content, so a list that fits (for instance with every list folded) shows no
    /// scroll bar, but no taller than the limit. Until the content has been measured, a rough guess.
    private var visibleHeight: CGFloat {
        let limit = min(max(maxHeight, Self.minimumHeight), screenLimit)
        let guess = Double(model.sections.reduce(0) { $0 + 52 + ($1.items.count * 42) })
        return CGFloat(min(contentHeight.map(Double.init) ?? guess, limit))
    }

    /// Drag to make the list taller or shorter; double-click to go back to the default.
    private var resizeHandle: some View {
        Capsule()
            .fill(Color.primary.opacity(gripHovering ? 0.35 : 0.18))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .contentShape(Rectangle())
            .onHover { inside in
                gripHovering = inside
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStartHeight ?? Double(visibleHeight)
                        dragStartHeight = start
                        maxHeight = min(max(start + drag.translation.height, Self.minimumHeight), screenLimit)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .onTapGesture(count: 2) { maxHeight = Self.defaultMaxHeight }
            .help("Drag to resize the list. Double-click to reset.")
            .accessibilityLabel("Resize the list")
            .animation(.snappy(duration: 0.3), value: gripHovering)
    }

    /// Changes whenever a section or task appears, disappears or moves, to drive the list animation.
    private var layoutKey: [String] {
        model.sections.map { section in
            model.collapsedListIDs.contains(section.id) ? section.id : section.id + ":" + section.items.map(\.id).joined(separator: ",")
        }
    }
}

/// Gives the scroll view around the list the slim, auto-hiding scroll bar instead of the wide one that is
/// always shown when a mouse is connected. SwiftUI has no setting for this, so it reaches the AppKit scroll view.
private struct ThinScrollers: NSViewRepresentable {
    let handle: ScrollHandle

    func makeNSView(context: Context) -> NSView { ConfiguringView(handle: handle) }
    func updateNSView(_ view: NSView, context: Context) { (view as? ConfiguringView)?.configure() }

    private final class ConfiguringView: NSView {
        let handle: ScrollHandle

        init(handle: ScrollHandle) {
            self.handle = handle
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The scroll view around us may not be laid out yet, so look on the next turn.
            DispatchQueue.main.async { [weak self] in self?.configure() }
        }

        func configure() {
            guard let scrollView = enclosingScrollView ?? scrollViewCovering() else { return }
            handle.scrollView = scrollView
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.controlSize = .mini
        }

        /// SwiftUI doesn't always make a background view a child of the scroll view, so find the one that covers it.
        private func scrollViewCovering() -> NSScrollView? {
            guard let root = window?.contentView else { return nil }
            let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            var found: NSScrollView?
            func search(_ candidate: NSView) {
                if let scroll = candidate as? NSScrollView, scroll.convert(scroll.bounds, to: nil).contains(center) {
                    found = scroll
                }
                candidate.subviews.forEach(search)
            }
            search(root)
            return found
        }
    }
}

/// The name of a section inside a list. Clicking it folds the section shut or open.
private struct SubheadingRow: View {
    let title: String
    let count: Int
    let folded: Bool
    let onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                if folded {
                    Text("\(count)")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(folded ? -90 : 0))
                    .opacity(hovering || folded ? 1 : 0.5)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.3), value: hovering)
        .help(folded ? "Show \(title)" : "Hide \(title)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A list's name and count. Clicking it folds the list shut or open.
private struct SectionHeader: View {
    let section: ReminderSection
    let collapsed: Bool
    let onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: section.list.symbol)
                    .foregroundStyle(section.list.color)
                Text(section.list.title).font(.subheadline.weight(.semibold))
                Text("\(section.items.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .contentTransition(.numericText())
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .opacity(hovering || collapsed ? 1 : 0.5)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.3), value: hovering)
        .animation(.snappy(duration: 0.4), value: collapsed)
        .help(collapsed ? "Show \(section.list.title)" : "Hide \(section.list.title)")
    }
}

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
    @State private var sectionDrag: SectionDrag?
    @State private var listDrag: ListDrag?
    @State private var renamingList: String?
    @State private var deletingList: String?
    @State private var scrollHandle = ScrollHandle()
    @State private var dragLoop: Task<Void, Never>?
    @State private var frames = RowFrames()
    @State private var justDragged = false
    /// Set when a drag was cancelled with Esc, until the mouse button is let go.
    @State private var dragCancelled = false
    @State private var escapeMonitor: Any?
    /// The list getting a new section, and the section being renamed.
    @State private var addingSectionTo: String?
    @State private var renamingSection: String?

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
            .overlay(alignment: .topLeading) { carriedCopy.zIndex(20) }
            .onDisappear {
                // The dropdown closing in the middle of a drag drops it.
                dragLoop?.cancel()
                stopWatchingKeys()
                drag = nil; sectionDrag = nil; listDrag = nil; dragCancelled = false
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.sections.enumerated()), id: \.element.id) { index, section in
                listBlock(index: index, section: section)
            }
        }
        .animation(.snappy(duration: 0.5), value: layoutKey)
        .animation(.snappy(duration: 0.4), value: model.collapsedParentIDs)
        .animation(.snappy(duration: 0.4), value: model.collapsedSectionIDs)
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) { dropIndicator }
    }

    @ViewBuilder private func listBlock(index: Int, section: ReminderSection) -> some View {
        if index > 0 { Divider().padding(.vertical, 6) }
        let collapsed = model.collapsedListIDs.contains(section.id)
        if renamingList == section.id {
            NameField(initial: section.list.title, placeholder: "List name", onSubmit: { name in
                model.renameList(section.list, to: name)
                withAnimation(Self.quick) { renamingList = nil }
            }, onCancel: { withAnimation(Self.quick) { renamingList = nil } })
        } else {
            SectionHeader(section: section, collapsed: collapsed, onToggle: {
                if !justDragged { withAnimation(.snappy(duration: 0.4)) { model.toggleCollapsed(section.list) } }
            }, onAddSection: section.list.isSmart ? nil : { withAnimation(Self.quick) { addingSectionTo = section.id } },
               onRename: section.list.isSmart ? nil : { withAnimation(Self.quick) { renamingList = section.id } },
               onDelete: section.list.isSmart ? nil : { withAnimation(Self.quick) { deletingList = section.id } })
            .contextMenu {
                if !section.list.isSmart {
                    Button("New Section…") { withAnimation(Self.quick) { addingSectionTo = section.id } }
                    Button("Rename List…") { withAnimation(Self.quick) { renamingList = section.id } }
                    Divider()
                    Button("Delete List…", role: .destructive) { withAnimation(Self.quick) { deletingList = section.id } }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames.headers[section.id] = $0 }
            .opacity(listDrag?.listID == section.id ? 0 : 1)   // the carried copy is drawn on top
            .simultaneousGesture(listDragGesture(section))
        }
        if deletingList == section.id {
            ListDeleteConfirmation(title: section.list.title, onCancel: { withAnimation(Self.quick) { deletingList = nil } }) {
                model.deleteList(section.list)
                withAnimation(Self.quick) { deletingList = nil }
            }
        }
        if addingSectionTo == section.id {
            NameField(placeholder: "Section name", onSubmit: { name in
                model.addSection(named: name, to: section.list)
                withAnimation(Self.quick) { addingSectionTo = nil }
            }, onCancel: { withAnimation(Self.quick) { addingSectionTo = nil } })
        }
        if !collapsed {
            let entries = section.entries(foldedParents: model.collapsedParentIDs, foldedSections: model.collapsedSectionIDs)
            if entries.isEmpty {
                Text("No reminders")
                    .font(.callout).foregroundStyle(.tertiary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
            }
            ForEach(entries) { entry in
                switch entry {
                case .heading(let info, let count, let folded):
                    if renamingSection == info.id {
                        NameField(initial: info.title, placeholder: "Section name", onSubmit: { name in
                            model.renameSection(info.id, in: section.list, to: name)
                            withAnimation(Self.quick) { renamingSection = nil }
                        }, onCancel: { withAnimation(Self.quick) { renamingSection = nil } })
                    } else {
                        SubheadingRow(title: info.title, count: count, folded: folded, onToggle: {
                            if !justDragged { withAnimation(.snappy(duration: 0.4)) { model.toggleSection(info.id) } }
                        }, onRename: { withAnimation(Self.quick) { renamingSection = info.id } },
                           onMove: { model.moveSection(info.id, in: section.list, by: $0) },
                           canMoveUp: info.index > 0, canMoveDown: info.index < section.sections.count - 1,
                           onDelete: { model.deleteSection(info.id, in: section.list) })
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames.headings[section.id + "|" + info.id] = $0 }
                        .onDisappear { frames.headings[section.id + "|" + info.id] = nil }
                        .opacity(sectionDrag?.section.id == info.id && sectionDrag?.listID == section.id ? 0 : 1)
                        .simultaneousGesture(sectionDragGesture(info, in: section))
                    }
                case .noSection:
                    SubheadingRow(title: "No Section", count: 0, folded: false, onToggle: {}, foldable: false)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames.headings[section.id + "|none"] = $0 }
                        .onDisappear { frames.headings[section.id + "|none"] = nil }
                case .item(let item):
                    let carried = drag?.item.id == item.id && drag?.sectionID == section.id
                    TaskRow(item: item, model: model, start: { if !justDragged { onStart(item) } }, done: { model.completeOnly(item) })
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames.rows[section.id + "|" + item.id] = $0 }
                        .onDisappear { frames.rows[section.id + "|" + item.id] = nil }
                        .opacity(carried ? 0 : 1)
                        .simultaneousGesture(dragGesture(item, in: section))
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                removal: .opacity.combined(with: .scale(scale: 0.95))))
                }
            }
        }
    
    }

    // MARK: Carrying

    private static let space = "taskList"

    /// Used only if a row's place is somehow unknown when it is picked up: a row-sized box around the mouse.
    private static func fallbackRect(near point: CGPoint) -> CGRect {
        CGRect(x: 0, y: point.y - 18, width: 296, height: 36)
    }
    /// The quick fade used for the name boxes and the delete card.
    private static let quick = Animation.snappy(duration: 0.2)

    private var resolver: DropResolver {
        DropResolver(sections: model.sections, collapsedLists: model.collapsedListIDs, collapsedParents: model.collapsedParentIDs,
                     collapsedSections: model.collapsedSectionIDs, frames: frames, hasSubtasks: model.hasSubtasks)
    }

    /// The carried row, drawn above the list rather than inside it, so the scroll view can't cut it off
    /// when it is carried past the edge. It sits where it was picked up plus how far the mouse has moved.
    @ViewBuilder private var carriedCopy: some View {
        if let drag {
            carried(rect: drag.rect, translation: drag.translation) {
                TaskRow(item: drag.item, model: model, start: {}, done: {})
            }
        } else if let sectionDrag {
            carried(rect: sectionDrag.rect, translation: sectionDrag.translation) {
                SubheadingRow(title: sectionDrag.section.title,
                              count: model.sections.first { $0.id == sectionDrag.listID }?.items.filter { $0.sectionID == sectionDrag.section.id }.count ?? 0,
                              folded: model.collapsedSectionIDs.contains(sectionDrag.section.id), onToggle: {})
            }
        } else if let listDrag, let section = model.sections.first(where: { $0.id == listDrag.listID }) {
            carried(rect: listDrag.rect, translation: listDrag.translation) {
                SectionHeader(section: section, collapsed: model.collapsedListIDs.contains(section.id), onToggle: {})
            }
        }
    }

    private func carried<Content: View>(rect: CGRect, translation: CGSize, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: rect.width, height: rect.height, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
            .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            .scaleEffect(1.02)
            .allowsHitTesting(false)
            // From content to view coordinates: the scroll offset comes off, and sideways movement is held in.
            .offset(x: rect.minX + min(max(translation.width, -10), 10),
                    y: rect.minY + translation.height - scrollHandle.offset)
    }

    /// Picking a reminder up and carrying it. The row follows the mouse; what is under it lights up.
    private func dragGesture(_ item: ReminderItem, in section: ReminderSection) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil {
                    guard !dragCancelled, sectionDrag == nil, listDrag == nil, let pointer = scrollHandle.pointer else { return }
                    // The mouse has already moved a few points; the row starts from where it was pressed.
                    let start = CGPoint(x: pointer.x - value.translation.width, y: pointer.y - value.translation.height)
                    drag = TaskDrag(item: item, sectionID: section.id, start: start, location: pointer,
                                    rect: frames.rows[section.id + "|" + item.id] ?? Self.fallbackRect(near: start))
                    startFollowing()
                }
                followMouse()
            }
            .onEnded { _ in dragCancelled = false; finishDrag() }
    }

    private func startFollowing() {
        // Esc puts everything back where it was. The key is taken, so it doesn't close the dropdown too.
        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53 else { return event }
                Task { @MainActor in cancelDrag() }
                return nil
            }
        }
        dragLoop?.cancel()
        dragLoop = Task { @MainActor in
            while !Task.isCancelled {
                followMouse()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Moves the carried row to the mouse and scrolls the list when the mouse is near its top or bottom edge,
    /// or past it.
    private func followMouse() {
        guard drag != nil || sectionDrag != nil || listDrag != nil, let pointer = scrollHandle.pointer else { return }
        // Esc is read straight from the keyboard, so it works however the keys reach the app.
        if CGEventSource.keyState(.combinedSessionState, key: 0x35) { return cancelDrag() }
        // The mouse button was let go somewhere the gesture didn't hear about.
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return finishDrag() }
        let zone: CGFloat = 36
        let fromTop = pointer.y - scrollHandle.offset
        // The visible part of the list, as drawn: never taller than the scroll view says.
        let viewport = min(scrollHandle.viewportHeight, visibleHeight)
        let fromBottom = scrollHandle.offset + viewport - pointer.y
        if fromTop < zone { scrollHandle.scroll(by: -scrollSpeed(zone - fromTop, zone)) }
        else if fromBottom < zone { scrollHandle.scroll(by: scrollSpeed(zone - fromBottom, zone)) }
        // Read again, since scrolling moves what is under the mouse.
        let location = scrollHandle.pointer ?? pointer
        if var current = drag, current.location != location { current.location = location; drag = current }
        if var current = sectionDrag, current.location != location { current.location = location; sectionDrag = current }
        if var current = listDrag, current.location != location { current.location = location; listDrag = current }
    }

    /// A slow crawl at the edge that picks up the further past it the mouse is, up to about 9 points a frame.
    private func scrollSpeed(_ depth: CGFloat, _ zone: CGFloat) -> CGFloat {
        1.5 + min(max(depth / zone, 0), 1.5) * 5
    }

    private func stopWatchingKeys() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    /// Drops whatever is being carried without doing anything with it.
    private func cancelDrag() {
        guard drag != nil || sectionDrag != nil || listDrag != nil else { return }
        dragLoop?.cancel()
        dragLoop = nil
        stopWatchingKeys()
        dragCancelled = true
        justDragged = true
        Task { try? await Task.sleep(for: .seconds(0.3)); justDragged = false }
        withAnimation(.snappy(duration: 0.3)) { drag = nil; sectionDrag = nil; listDrag = nil }
    }

    private func finishDrag() {
        dragLoop?.cancel()
        dragLoop = nil
        stopWatchingKeys()
        justDragged = true
        Task { try? await Task.sleep(for: .seconds(0.3)); justDragged = false }
        if let finished = sectionDrag {
            let slot = resolver.sectionSlot(moving: finished.section, in: finished.listID, at: finished.location)
            withAnimation(.snappy(duration: 0.35)) { sectionDrag = nil }
            if let slot, slot.index != finished.section.index,
               let list = model.sections.first(where: { $0.id == finished.listID })?.list {
                model.moveSection(finished.section.id, in: list, toIndex: slot.index)
            }
        } else if let finished = listDrag {
            let slot = resolver.listSlot(moving: finished.listID, at: finished.location)
            withAnimation(.snappy(duration: 0.35)) { listDrag = nil }
            // No change when it would land where it already is.
            let ids = model.sections.map(\.id)
            if let slot, let from = ids.firstIndex(of: finished.listID), let target = ids.firstIndex(of: slot.target) {
                let landing = slot.after ? target + 1 : target
                if landing != from, landing != from + 1 { model.moveList(finished.listID, nextTo: slot.target, after: slot.after) }
            }
        } else if let finished = drag {
            let target = resolver.target(moving: finished.item, at: finished.location)
            withAnimation(.snappy(duration: 0.35)) { drag = nil }
            if let target { perform(target.action, for: finished.item) }
        }
    }

    private func perform(_ action: DropAction, for item: ReminderItem) {
        switch action {
        case .reorder(let target, let after): model.reorder(item, nextTo: target, after: after)
        case .move(let list): model.move(item, toListID: list.id)
        case .flag: model.setFlag(item, to: true)
        case .today: model.setDay(item, to: Date())
        case .subtask(let parent): model.makeSubtask(item, of: parent)
        case .promote(let target, let after): model.promote(item, nextTo: target, after: after)
        case .section(let id, _): model.move(item, toSection: id)
        }
    }

    private func listDragGesture(_ section: ReminderSection) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if listDrag == nil {
                    guard !dragCancelled, drag == nil, sectionDrag == nil, let pointer = scrollHandle.pointer else { return }
                    let start = CGPoint(x: pointer.x - value.translation.width, y: pointer.y - value.translation.height)
                    listDrag = ListDrag(listID: section.id, start: start, location: pointer,
                                    rect: frames.headers[section.id] ?? Self.fallbackRect(near: start))
                    startFollowing()
                }
                followMouse()
            }
            .onEnded { _ in dragCancelled = false; finishDrag() }
    }

    private func sectionDragGesture(_ info: ReminderKit.ListSection, in section: ReminderSection) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if sectionDrag == nil {
                    guard !dragCancelled, drag == nil, listDrag == nil, let pointer = scrollHandle.pointer else { return }
                    let start = CGPoint(x: pointer.x - value.translation.width, y: pointer.y - value.translation.height)
                    sectionDrag = SectionDrag(section: info, listID: section.id, start: start, location: pointer,
                                              rect: frames.headings[section.id + "|" + info.id] ?? Self.fallbackRect(near: start))
                    startFollowing()
                }
                followMouse()
            }
            .onEnded { _ in dragCancelled = false; finishDrag() }
    }

    /// The line or outline showing where the carried thing would land.
    @ViewBuilder private var dropIndicator: some View {
        if let listDrag, let slot = resolver.listSlot(moving: listDrag.listID, at: listDrag.location) {
            Capsule().fill(Color.accentColor)
                .frame(width: 292, height: 3)
                .offset(x: 2, y: slot.lineY - 1.5)
        } else if let sectionDrag, let slot = resolver.sectionSlot(moving: sectionDrag.section, in: sectionDrag.listID, at: sectionDrag.location),
                  slot.index != sectionDrag.section.index {
            Capsule().fill(Color.accentColor)
                .frame(width: 272, height: 3)
                .offset(x: 6, y: slot.lineY - 1.5)
        } else if let drag, let target = resolver.target(moving: drag.item, at: drag.location) {
            let rect = target.rect
            if case .reorder(_, let after) = target.action {
                Capsule().fill(Color.accentColor)
                    .frame(width: max(rect.width - 12, 0), height: 3)
                    .offset(x: rect.minX + 6, y: (after ? rect.maxY : rect.minY) - 1.5)
            } else if case .promote(let anchor, let after) = target.action, anchor != nil {
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
    var onRename: () -> Void = {}
    var onMove: (Int) -> Void = { _ in }
    var canMoveUp = false
    var canMoveDown = false
    var onDelete: () -> Void = {}
    /// False for the title over reminders without a section: a plain label that can't be folded or edited.
    var foldable = true

    @State private var hovering = false

    var body: some View {
        if foldable { button } else { label }
    }

    private var label: some View {
        Text(title).font(.callout.weight(.semibold)).lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private var button: some View {
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
        .contextMenu {
            Button("Rename…", action: onRename)
            Button("Move Up") { onMove(-1) }.disabled(!canMoveUp)
            Button("Move Down") { onMove(1) }.disabled(!canMoveDown)
            Divider()
            Button("Delete Section", role: .destructive, action: onDelete)
        }
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
    var onAddSection: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

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
        // A + next to the chevron, only while the pointer is over the list's name.
        .overlay(alignment: .trailing) {
            if hovering, onAddSection != nil || onRename != nil {
                HStack(spacing: 0) {
                    if onRename != nil || onDelete != nil {
                        Menu {
                            if let onRename { Button("Rename List…", action: onRename) }
                            if let onDelete {
                                Divider()
                                Button("Delete List…", role: .destructive, action: onDelete)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        .fixedSize()
                        .help("More for \(section.list.title)")
                        .accessibilityLabel("More for \(section.list.title)")
                    }
                    if let onAddSection {
                        Button(action: onAddSection) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Add a section to \(section.list.title)")
                        .accessibilityLabel("Add a section to \(section.list.title)")
                    }
                }
                .padding(.trailing, 24)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.3), value: hovering)
        .animation(.snappy(duration: 0.4), value: collapsed)
        .help(collapsed ? "Show \(section.list.title)" : "Hide \(section.list.title)")
    }
}

/// Asked in the list itself, because a pop-up would close the dropdown.
private struct ListDeleteConfirmation: View {
    let title: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Delete “\(title)”?", systemImage: "trash")
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Text("This also deletes every reminder in it, in the Reminders app too. It can't be undone.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Delete", action: onDelete).buttonStyle(.borderedProminent).tint(.red)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

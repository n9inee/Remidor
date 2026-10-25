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
                        .background(ThinScrollers())
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
                if !collapsed {
                    ForEach(section.items) { item in
                        TaskRow(item: item, model: model, start: { onStart(item) }, done: { model.completeOnly(item) })
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                    removal: .opacity.combined(with: .scale(scale: 0.95))))
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.5), value: layoutKey)
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
    func makeNSView(context: Context) -> NSView { ConfiguringView() }
    func updateNSView(_ view: NSView, context: Context) { (view as? ConfiguringView)?.configure() }

    private final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The scroll view around us may not be laid out yet, so look on the next turn.
            DispatchQueue.main.async { [weak self] in self?.configure() }
        }

        func configure() {
            guard let scrollView = enclosingScrollView ?? scrollViewCovering() else { return }
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

//
//  CountdownMath.swift
//  Remidor
//
//  Created by n9ine on 10.11.2026.
//

import Foundation

/// The arithmetic behind the focus timer, kept apart from the clock so it can be tested.
enum CountdownMath {
    /// Seconds from `now` until `end`, never below zero.
    static func remaining(until end: Date, now: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(now))
    }

    /// The moment a countdown with `remaining` seconds left finishes, if it runs from `now`. Resuming a paused
    /// timer uses this, so the time spent paused doesn't count.
    static func end(after remaining: TimeInterval, from now: Date) -> Date {
        now.addingTimeInterval(max(0, remaining))
    }

    /// How full the ring is: 1 at the start, 0 when the time is up.
    static func progress(remaining: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, remaining / total))
    }

    static func isFinished(end: Date, now: Date) -> Bool { now >= end }
}

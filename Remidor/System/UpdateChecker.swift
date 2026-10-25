//
//  UpdateChecker.swift
//  Remidor
//
//  Created by n9ine on 23.10.2026.
//

import Foundation
import Observation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Remidor", category: "updates")

struct AvailableUpdate: Equatable {
    let version: String
    let url: URL
}

/// Asks GitHub whether a newer release exists and says so. It never downloads or installs anything:
/// the banner only opens the release page.
@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    nonisolated static let repository = "n9inee/Remidor"

    enum Status: Equatable {
        case idle, checking, upToDate
        case available(AvailableUpdate)
        case failed
    }

    private(set) var status = Status.idle

    /// Whether Remidor looks for updates by itself. The Check now button works either way.
    var isEnabled = UserDefaults.standard.object(forKey: DefaultsKey.checkForUpdates) as? Bool ?? true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.checkForUpdates) }
    }

    /// The version whose banner was closed with the ✕. A newer release shows a banner again.
    private var dismissedVersion = UserDefaults.standard.string(forKey: DefaultsKey.dismissedUpdate)

    /// The update to point out in the dropdown, unless its banner was closed.
    var availableUpdate: AvailableUpdate? {
        guard case .available(let update) = status, update.version != dismissedVersion else { return nil }
        return update
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    @ObservationIgnored private var loop: Task<Void, Never>?

    /// Checks shortly after launch and then about once a day. Development builds skip this, because they
    /// would always look out of date.
    func start() {
        #if !DEBUG
        guard loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                if let self, self.isEnabled, self.isDue { await self.checkNow() }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
        #endif
    }

    func checkNow() async {
        guard status != .checking else { return }
        status = .checking
        do {
            if let latest = try await Self.fetchLatest(appVersion: Self.currentVersion), Self.isNewer(latest.version, than: Self.currentVersion) {
                status = .available(latest)
            } else {
                status = .upToDate
            }
            UserDefaults.standard.set(Date(), forKey: DefaultsKey.lastUpdateCheck)
        } catch {
            log.error("Update check failed: \(error.localizedDescription)")
            status = .failed
        }
    }

    func dismissBanner() {
        guard case .available(let update) = status else { return }
        dismissedVersion = update.version
        UserDefaults.standard.set(update.version, forKey: DefaultsKey.dismissedUpdate)
    }

    private var isDue: Bool {
        guard let last = UserDefaults.standard.object(forKey: DefaultsKey.lastUpdateCheck) as? Date else { return true }
        return Date().timeIntervalSince(last) > 24 * 3600
    }

    // MARK: Talking to GitHub

    /// The newest published release, or nil if there is none yet.
    nonisolated private static func fetchLatest(appVersion: String) async throws -> AvailableUpdate? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }

        // A throwaway session keeps no cache or cookies on disk. The only thing the request says about this
        // Mac is the app name and version, which GitHub requires as a User-Agent.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "Remidor/\(appVersion)", "Accept": "application/vnd.github+json"]
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 15))
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return parse(data)
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let draft: Bool?
        let prerelease: Bool?
    }

    /// Reads GitHub's answer. Drafts, pre-releases and anything not pointing at this repository are ignored,
    /// so the banner can only ever open this project's own release page.
    nonisolated static func parse(_ data: Data) -> AvailableUpdate? {
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true,
              release.html_url.hasPrefix("https://github.com/\(repository)/"),
              let url = URL(string: release.html_url) else { return nil }
        let version = release.tag_name.drop { $0 == "v" || $0 == "V" }
        guard !version.isEmpty else { return nil }
        return AvailableUpdate(version: String(version), url: url)
    }

    /// Compares dotted versions number by number, so 1.10 is newer than 1.9. Anything after a `-` is ignored.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        func numbers(_ version: String) -> [Int] {
            version.drop { $0 == "v" || $0 == "V" }
                .split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let (a, b) = (numbers(remote), numbers(local))
        for index in 0..<max(a.count, b.count) {
            let (x, y) = (index < a.count ? a[index] : 0, index < b.count ? b[index] : 0)
            if x != y { return x > y }
        }
        return false
    }
}

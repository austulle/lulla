import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// JSON file in the shared App Group container, read and written by the app,
/// the widget extension and App Intents. Every write is a locked
/// read-modify-write (flock across processes), so a widget button and the
/// app can't clobber each other.
final class LogStore: @unchecked Sendable {
    static let appGroup = "group.com.lull.baby"
    static let shared = LogStore(url: LogStore.defaultURL())

    let url: URL
    private let lockURL: URL
    private let threadLock = NSLock()

    init(url: URL) {
        self.url = url
        self.lockURL = url.appendingPathExtension("lock")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    static func defaultURL() -> URL {
        let fm = FileManager.default
        #if canImport(Darwin)
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group.appendingPathComponent("lull-log.json")
        }
        #endif
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("Lull/lull-log.json")
    }

    func load() -> LogData {
        withLock { read() }
    }

    @discardableResult
    func update(_ body: (inout LogData) throws -> Void) rethrows -> LogData {
        try withLock {
            var data = read()
            try body(&data)
            write(data)
            return data
        }
    }

    // MARK: - Private

    private func read() -> LogData {
        guard let raw = try? Data(contentsOf: url) else { return LogData() }
        do {
            return try Self.decoder.decode(LogData.self, from: raw)
        } catch {
            // Never silently drop a log we can't parse: keep a copy aside.
            let backup = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? raw.write(to: backup)
            return LogData()
        }
    }

    private func write(_ data: LogData) {
        guard let raw = try? Self.encoder.encode(data) else { return }
        try? raw.write(to: url, options: [.atomic])
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        threadLock.lock()
        defer { threadLock.unlock() }
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        return try body()
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

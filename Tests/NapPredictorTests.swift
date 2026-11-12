import XCTest
@testable import Lulla

final class NapPredictorTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-11-12 at hh:mm (UTC), offset by `day` days.
    private func at(_ h: Int, _ m: Int = 0, day: Int = 0) -> Date {
        let base = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: h, minute: m))!
        return base.addingTimeInterval(Double(day) * 86400)
    }

    private func profile(ageDays: Int, dueOffsetDays: Int? = nil) -> BabyProfile {
        let birth = at(12).addingTimeInterval(-Double(ageDays) * 86400)
        let due = dueOffsetDays.map { birth.addingTimeInterval(Double($0) * 86400) }
        return BabyProfile(name: "Mila", birthDate: birth, dueDate: due)
    }

    private func predictor() -> NapPredictor { NapPredictor(calendar: cal) }

    func testBandLookup() {
        XCTAssertEqual(WakeWindows.band(forAgeDays: 0).label, "0–4 weeks")
        XCTAssertEqual(WakeWindows.band(forAgeDays: 98).label, "3–4 months")
        XCTAssertEqual(WakeWindows.band(forAgeDays: 300).naps, 2)
        XCTAssertEqual(WakeWindows.band(forAgeDays: 2000).label, "2–3 years")
    }

    func testWindowsLengthenThroughTheDay() {
        let band = WakeWindows.band(forAgeDays: 150)
        let first = WakeWindows.range(for: band, index: 0)
        let last = WakeWindows.range(for: band, index: band.naps)
        XCTAssertEqual(first, band.first)
        XCTAssertEqual(last, band.last)
        XCTAssertLessThan(first.mid, WakeWindows.range(for: band, index: 1).mid)
        XCTAssertLessThan(WakeWindows.range(for: band, index: 1).mid, last.mid)
    }

    func testFirstNapAfterMorningWake() throws {
        // 14 weeks → 3–4 months band, first window 75–90 min (mid 82.5).
        let data = LogData(profile: profile(ageDays: 98),
                           entries: [.sleep(start: at(19, 30, day: -1), end: at(6, 45))])
        let p = try XCTUnwrap(predictor().predict(data, now: at(7, 0)))
        XCTAssertEqual(p.kind, .nap)
        XCTAssertEqual(p.napNumber, 1)
        XCTAssertEqual(p.target, at(6, 45).addingTimeInterval(82.5 * 60))
        XCTAssertEqual(p.windowStart, p.target.addingTimeInterval(-10 * 60))
        XCTAssertEqual(p.windowEnd, p.target.addingTimeInterval(10 * 60))
        XCTAssertFalse(p.personalized)
        XCTAssertFalse(p.shortNapAdjusted)
        XCTAssertEqual(p.phase(at: at(7, 0)), .upcoming)
        XCTAssertEqual(p.phase(at: p.target), .open)
        XCTAssertEqual(p.phase(at: p.windowEnd.addingTimeInterval(60)), .late)
    }

    func testThirdNapAfterTwoNaps() throws {
        let data = LogData(profile: profile(ageDays: 98), entries: [
            .sleep(start: at(19, 30, day: -1), end: at(6, 45)),
            .sleep(start: at(8, 10), end: at(9, 20)),
            .sleep(start: at(10, 50), end: at(12, 0)),
        ])
        let p = try XCTUnwrap(predictor().predict(data, now: at(12, 5)))
        XCTAssertEqual(p.kind, .nap)
        XCTAssertEqual(p.napNumber, 3)
        let band = WakeWindows.band(forAgeDays: 98)
        XCTAssertEqual(p.typicalMinutes, WakeWindows.range(for: band, index: 2))
    }

    func testShortNapShortensNextWindow() throws {
        let entries: [Entry] = [
            .sleep(start: at(19, 30, day: -1), end: at(6, 45)),
            .sleep(start: at(8, 10), end: at(8, 35)), // 25 min
        ]
        let p = try XCTUnwrap(predictor().predict(LogData(profile: profile(ageDays: 98), entries: entries), now: at(8, 40)))
        XCTAssertTrue(p.shortNapAdjusted)
        XCTAssertEqual(p.targetMinutes, p.typicalMinutes.mid * NapPredictor.shortNapFactor, accuracy: 0.001)
    }

    func testBedtimeAfterLastNap() throws {
        // 9 months → 2 naps; after the second nap comes bedtime.
        let data = LogData(profile: profile(ageDays: 280), entries: [
            .sleep(start: at(19, 0, day: -1), end: at(6, 30)),
            .sleep(start: at(9, 30), end: at(10, 45)),
            .sleep(start: at(14, 0), end: at(15, 15)),
        ])
        let p = try XCTUnwrap(predictor().predict(data, now: at(15, 30)))
        XCTAssertEqual(p.kind, .bedtime)
        XCTAssertEqual(p.title, "Bedtime")
        XCTAssertEqual(p.typicalMinutes, WakeWindows.band(forAgeDays: 280).last)
    }

    func testLateNapBecomesBedtime() throws {
        // 5 months, only one nap logged but it ended at 16:30: a nap target
        // past 18:00 turns into bedtime.
        let data = LogData(profile: profile(ageDays: 160), entries: [
            .sleep(start: at(15, 0), end: at(16, 30)),
        ])
        let p = try XCTUnwrap(predictor().predict(data, now: at(16, 35)))
        XCTAssertEqual(p.kind, .bedtime)
    }

    func testNightWakingHasNoWindow() {
        let data = LogData(profile: profile(ageDays: 98),
                           entries: [.sleep(start: at(19, 0, day: -1), end: at(1, 30))])
        XCTAssertNil(predictor().predict(data, now: at(1, 45)))
        let snap = LullaSnapshot.make(data, now: at(1, 45), calendar: cal)
        XCTAssertTrue(snap.isNightWaking)
        XCTAssertEqual(snap.mood, .night)
    }

    func testNoPredictionWhileAsleepOrWithoutHistory() {
        var data = LogData(profile: profile(ageDays: 98))
        XCTAssertNil(predictor().predict(data, now: at(9)))
        data.startSleep(at: at(8))
        XCTAssertNil(predictor().predict(data, now: at(9)))
    }

    func testStaleLogGivesNoPrediction() {
        let data = LogData(profile: profile(ageDays: 98),
                           entries: [.sleep(start: at(19, 0, day: -2), end: at(6, 0, day: -1))])
        XCTAssertNil(predictor().predict(data, now: at(9)))
    }

    func testPersonalizationLearnsLongerWindows() throws {
        // 5 months (first window 105–120, mid 112.5). For a week this baby
        // has happily stayed up ~25% longer before nap 1.
        var entries: [Entry] = []
        for d in -6...0 {
            entries.append(.sleep(start: at(19, 0, day: d - 1), end: at(6, 30, day: d)))
            if d < 0 {
                entries.append(.sleep(start: at(6, 30, day: d).addingTimeInterval(140 * 60),
                                      end: at(10, 20, day: d)))
            }
        }
        let data = LogData(profile: profile(ageDays: 160), entries: entries)
        let pred = predictor()
        let sleeps = data.completedSleeps.sorted { $0.start < $1.start }
        let (factor, samples) = pred.personalFactor(sleeps: sleeps, profile: data.profile!, now: at(6, 40))
        XCTAssertGreaterThanOrEqual(samples, 6)
        XCTAssertGreaterThan(factor, 1.05)
        XCTAssertLessThanOrEqual(factor, 1.125)

        let p = try XCTUnwrap(pred.predict(data, now: at(6, 40)))
        XCTAssertTrue(p.personalized)
        XCTAssertGreaterThan(p.targetMinutes, p.typicalMinutes.mid)
        XCTAssertLessThanOrEqual(p.targetMinutes, p.typicalMinutes.upperBound * 1.2)
    }

    func testCorrectedAge() {
        // Born 30 days ago, 42 days early → corrected age 0.
        let p = profile(ageDays: 30, dueOffsetDays: 42)
        XCTAssertEqual(p.ageInDays(at: at(12), calendar: cal), 0)
        XCTAssertEqual(profile(ageDays: 30).ageInDays(at: at(12), calendar: cal), 30)
    }
}

final class LogDataTests: XCTestCase {
    func testSwitchingSidesClosesRunningFeed() {
        var d = LogData()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        d.startBreast(.left, at: t0)
        d.startBreast(.right, at: t0.addingTimeInterval(600))
        XCTAssertEqual(d.entries.count, 2)
        XCTAssertEqual(d.entries[0].end, t0.addingTimeInterval(600))
        XCTAssertEqual(d.activeFeed?.side, .right)
        XCTAssertEqual(d.suggestedSide, .left)
        d.stopFeed(at: t0.addingTimeInterval(900))
        XCTAssertNil(d.activeFeed)
    }

    func testSleepToggleAndOrdering() {
        var d = LogData()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertTrue(d.startSleep(at: t0))
        XCTAssertFalse(d.startSleep(at: t0))
        d.add(.bottle(ml: 90, content: nil, at: t0.addingTimeInterval(-60)))
        XCTAssertEqual(d.entries.first?.kind, .feed)
        let ended = d.endSleep(at: t0.addingTimeInterval(3600))
        XCTAssertEqual(ended?.duration(), 3600)
        XCTAssertNil(d.activeSleep)
    }

    func testPauseResumeExcludesPausedTime() {
        var d = LogData()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        d.startSleep(at: t0)
        XCTAssertEqual(d.togglePause(.sleep, at: t0.addingTimeInterval(600)), true)
        XCTAssertTrue(d.activeSleep!.isPaused)
        // While paused the duration stays frozen at 10 min.
        XCTAssertEqual(d.activeSleep!.duration(at: t0.addingTimeInterval(900)), 600)
        XCTAssertEqual(d.togglePause(.sleep, at: t0.addingTimeInterval(1200)), false)
        XCTAssertEqual(d.activeSleep!.timerAnchor, t0.addingTimeInterval(600))
        let ended = d.endSleep(at: t0.addingTimeInterval(1800))
        XCTAssertEqual(ended?.duration(), 1200) // 30 min minus a 10 min pause
        XCTAssertNil(d.togglePause(.sleep, at: t0))
    }

    func testStoppingWhilePausedEndsAtThePause() {
        var d = LogData()
        let t0 = Date(timeIntervalSince1970: 4_000_000)
        d.startBreast(.left, at: t0)
        d.togglePause(.feed, at: t0.addingTimeInterval(300))
        let stopped = d.stopFeed(at: t0.addingTimeInterval(900))
        XCTAssertEqual(stopped?.end, t0.addingTimeInterval(300))
        XCTAssertEqual(stopped?.duration(), 300)
        XCTAssertNil(stopped?.pausedAt)
    }

    func testStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("log.json")
        let store = LogStore(url: url)
        XCTAssertEqual(store.load(), LogData())
        let birth = Date(timeIntervalSince1970: 1_700_000_000)
        store.update { d in
            d.profile = BabyProfile(name: "Mila", birthDate: birth)
            d.add(.bottle(ml: 120, content: .formula, at: birth.addingTimeInterval(86400)))
        }
        let reloaded = LogStore(url: url).load()
        XCTAssertEqual(reloaded.profile?.name, "Mila")
        XCTAssertEqual(reloaded.entries.first?.amountML, 120)
    }

    func testProfileDecodesWithMissingNewerFields() throws {
        let json = #"{"name":"Mila","birthDate":1700000000}"#.data(using: .utf8)!
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        let p = try d.decode(BabyProfile.self, from: json)
        XCTAssertEqual(p.feedingStyle, .breast)
        XCTAssertEqual(p.defaultBottleML, 120)
    }

    func testFormat() {
        XCTAssertEqual(Format.duration(42 * 60), "42m")
        XCTAssertEqual(Format.duration(78 * 60), "1h 18m")
        XCTAssertEqual(Format.duration(120 * 60), "2h")
        XCTAssertEqual(Format.minutes(75), "1h15")
        XCTAssertEqual(Format.age(days: 98), "14 wk")
        XCTAssertEqual(Format.volume(ml: 120, unit: .oz), "4.1 oz")
    }
}

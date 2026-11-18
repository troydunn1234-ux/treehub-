import Foundation
import SwiftData

/// The Still Pointz / Apple Health breath sessions that go with a hug: finding them around the photo's time,
/// filling in all their data (practice, heart rate, HRV, breathing) and keeping it current as late Watch data
/// arrives. Read-only on Health; the Still Pointz feed comes from Shared/Wellness/WellnessBridge.swift.
@MainActor
enum HugSessions {
    /// Sessions within this window of the photo / hug time are offered (and preselected).
    nonisolated static let window: TimeInterval = 60 * 60

    private static func feed() -> [WellnessBridge.Session] {
        (WellnessBridge.stillPoint()?.sessions ?? []).filter { $0.isCalm && $0.minutes >= 1 }
    }

    private static func fromFeed(_ f: WellnessBridge.Session) -> LinkedSession { linked(from: f) }

    /// One Still Pointz feed session as a hug's linked session, with all the heart data the feed has.
    nonisolated static func linked(from f: WellnessBridge.Session) -> LinkedSession {
        var s = LinkedSession(feedID: f.id, start: f.date, end: f.end ?? f.date.addingTimeInterval(f.minutes * 60),
                              source: "Still Pointz", practice: f.practice, avgHR: f.avgHR, minHR: f.minHR,
                              startHR: f.startHR, hrDrop: f.hrDrop, hrv: f.hrv, respRate: f.respRate)
        s.endHR = f.endHR
        s.calmSeconds = f.calmSeconds
        s.pacedBPM = f.breathsPerMin
        return s
    }

    /// Still Pointz feed sessions that go with a hug at `date` (a photo's capture time): guided practice of a minute
    /// or more (no sauna / steam) starting within ±60 min, nearest first. Pure, so it's testable.
    nonisolated static func feedCandidates(near date: Date, in sessions: [WellnessBridge.Session]) -> [LinkedSession] {
        sessions
            .filter { $0.isCalm && $0.minutes >= 1 && abs($0.date.timeIntervalSince(date)) <= window }
            .sorted { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            .map { linked(from: $0) }
    }

    /// Every breath session within ±60 min of `date`: Still Pointz' feed first (practice names), then Apple Health
    /// mindful sessions and breathwork workouts not already listed. Nearest first.
    static func candidates(near date: Date) async -> [LinkedSession] {
        var out = feedCandidates(near: date, in: WellnessBridge.stillPoint()?.sessions ?? [])
        let hs = HealthService.shared
        if hs.isAvailable && !DemoData.isOn {
            let health = await hs.mindfulSessions(around: date, hours: 1) + hs.breathworkWorkouts(around: date, hours: 1)
            for h in health where h.minutes >= 1 && abs(h.start.timeIntervalSince(date)) <= window {
                let s = LinkedSession(start: h.start, end: h.end, source: h.source)
                if !out.contains(where: { $0.sameSession(as: s) }) { out.append(s) }
            }
        }
        return out.sorted { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }

    /// Sessions that overlap a hug's own time window: how hugs logged before multi-linking (one session, or just
    /// a date and a length) get their sessions back.
    static func overlapping(_ hug: Hug) async -> [LinkedSession] {
        let from = hug.date.addingTimeInterval(30)
        let to = hug.date.addingTimeInterval(max(hug.durationMin, 1) * 60 - 30)
        return await candidates(near: hug.date).filter { $0.end > from && $0.start < to }
    }

    /// Re-read the Still Pointz feed and Apple Health for one session's window and fill in everything known.
    static func enrich(_ s: LinkedSession) async -> LinkedSession {
        var out = s
        if let f = feed().first(where: { s.feedID != nil ? $0.id == s.feedID : abs($0.date.timeIntervalSince(s.start)) < 90 }) {
            let ff = fromFeed(f)
            out.feedID = out.feedID ?? ff.feedID
            out.practice = ff.practice ?? out.practice
            if out.source.isEmpty || out.feedID != nil { out.source = "Still Pointz" }
            out.avgHR = ff.avgHR ?? out.avgHR; out.minHR = ff.minHR ?? out.minHR
            out.startHR = ff.startHR ?? out.startHR; out.hrDrop = ff.hrDrop ?? out.hrDrop; out.hrv = ff.hrv ?? out.hrv
            out.endHR = ff.endHR ?? out.endHR; out.respRate = ff.respRate ?? out.respRate
            out.calmSeconds = ff.calmSeconds ?? out.calmSeconds; out.pacedBPM = ff.pacedBPM ?? out.pacedBPM
        }
        let hs = HealthService.shared
        guard hs.isAvailable, !DemoData.isOn else { return out }
        let st = await hs.breathStats(from: out.start, to: out.end)
        out.avgHR = out.avgHR ?? st.avgHR.map { $0.rounded() }
        out.minHR = out.minHR ?? st.minHR.map { $0.rounded() }
        out.startHR = out.startHR ?? st.startHR.map { $0.rounded() }
        out.endHR = out.endHR ?? st.endHR.map { $0.rounded() }
        out.hrDrop = out.hrDrop ?? st.hrDrop
        out.hrv = out.hrv ?? st.hrv
        if out.maxHR == nil, let hr = await hs.heartRate(from: out.start, to: out.end) { out.maxHR = hr.max.rounded() }
        if out.respRate == nil, let rr = await hs.respiratoryRate(from: out.start, to: out.end) { out.respRate = (rr * 10).rounded() / 10 }
        return out
    }

    static func enrich(_ list: [LinkedSession]) async -> [LinkedSession] {
        var out: [LinkedSession] = []
        for s in list { out.append(await enrich(s)) }
        return out
    }

    /// Bring a hug's linked sessions up to date. Older hugs (no list yet) get theirs by matching the hug's
    /// time window, once. Saves only when something changed.
    static func refresh(_ hug: Hug, context: ModelContext) async {
        let base = hug.hasLinkList ? hug.linkedSessions : await overlapping(hug)
        let fresh = await enrich(base)
        // Deleted (or its store closed) while Health was answering: nothing to update.
        guard !hug.isDeleted, hug.modelContext != nil else { return }
        guard !hug.hasLinkList || fresh != hug.linkedSessions else { return }
        hug.linkedSessions = fresh
        try? context.save()
    }

    static func refresh(_ hugs: [Hug], context: ModelContext) async {
        for h in hugs { await refresh(h, context: context) }
    }
}

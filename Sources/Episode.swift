import Foundation

// MARK: - Episode

struct Episode: Identifiable {
    let id: UUID
    let date: Date
    var title: String?
    var summary: String?
    var segments: [(start: TimeInterval, end: TimeInterval)]

    // MARK: - Computed

    var episodeCode: String { Self.code(from: date) }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    // MARK: - ISO 8601 Week Code

    /// Produces an episode code in the format `Y[YY]S[WW]E[DD]`
    /// using ISO 8601 week numbering (week starts Monday, week 1 contains Jan 4).
    static func code(from date: Date) -> String {
        let iso = Calendar(identifier: .iso8601)
        let year = iso.component(.yearForWeekOfYear, from: date) % 100
        let week = iso.component(.weekOfYear, from: date)
        let day  = iso.component(.weekday, from: date) // ISO 8601: 1=Mon … 7=Sun
        return String(format: "Y%02dS%02dE%02d", year, week, day)
    }

    // MARK: - Mock Data

    static func mockEpisodes(count: Int) -> [Episode] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let titles: [(String, String)] = [
            (
                "Widget architecture sprint & late-night diarization debugging",
                "Kicked off the dynamic widget system for AutoClawd with three layout variants. Spent the evening tracking down a speaker-diarization regression where overlapping segments caused misattribution. Fixed the sliding-window overlap logic."
            ),
            (
                "Beta feedback synthesis & influencer outreach planning",
                "Consolidated 47 pieces of Trippy beta feedback into actionable themes. Top requests: offline mode, shareable itineraries. Drafted outreach list for 12 travel micro-influencers and templated initial DMs."
            ),
            (
                "Y Combinator application deep-dive with Mukul",
                "Three-hour working session refining the YC W26 application. Rewrote the traction section with updated metrics. Mukul stress-tested the demo script; found two edge cases in the live transcription flow."
            ),
            (
                "Pipeline debugger UI scaffolding & raw chunk viewer",
                "Built the initial pipeline debugger tab with collapsible group rows. Each group shows raw chunks, cleaning output, analysis tags, and downstream tasks. Added colour-coded status pills."
            ),
            (
                "Ambient intelligence accuracy benchmarks on field recordings",
                "Ran 40 field recordings through the extraction pipeline. Precision at 82%, recall at 71%. Main failure mode: short utterances under 3 seconds getting dropped by the VAD gate. Tuned energy threshold."
            ),
            (
                "Flight booking MCP connector & personal task routing",
                "Prototyped a new MCP connector for flight searches. Hit a snag with OAuth token refresh on the Amadeus sandbox. Routed personal tasks to a separate queue so they don't block project work."
            ),
            (
                "Sustained transcript mode design & scroll anchoring",
                "Designed the sustained transcript widget variant that streams text in real-time. Solved the auto-scroll vs. user-scroll conflict with a scroll-anchor that disengages on manual scroll-up."
            ),
            (
                "Speaker diarization model fine-tuning session",
                "Fine-tuned the pyannote diarization model on 6 hours of in-office recordings. Improved DER from 18% to 12%. Still struggles with cross-talk in meeting rooms with hard reflections."
            ),
            (
                "Monotone theme exploration & accessibility audit",
                "Explored a new monotone/greyscale theme for reduced visual noise. Ran VoiceOver audit on the main panel; fixed 7 missing accessibility labels and 2 focus-order issues."
            ),
            (
                "World-model graph layout algorithm improvements",
                "Replaced the naive force-directed layout with a constrained version that respects clusters. People nodes now orbit their most-frequent place. Reduced layout jitter by 60%."
            ),
            (
                "Trippy API integration sprint planning with backend team",
                "Mapped out the next two-week sprint for Trippy API integration. Broke the booking flow into 8 tasks across 3 services. Set up Linear project board and assigned owners."
            ),
            (
                "AutoClawd MCP server launch & Claude Code integration",
                "Shipped the MCP server that lets Claude Code read and write AutoClawd data mid-task. Tested with project inference, transcript search, and todo creation. Wrote integration docs."
            ),
            (
                "Evening journaling & weekly review session",
                "Weekly review: shipped 3 features, closed 11 bugs, 2 PRs still in review. Personal reflection on work-life balance and sleep schedule. Set intentions for next week."
            ),
            (
                "Hotword detection overhaul & wake-word benchmarking",
                "Replaced the keyword-spotting model with a streaming CTC decoder. Benchmarked 5 wake-word candidates; 'Hey Clawd' had the best FRR/FAR trade-off at 2% / 0.3%. Integrated into the audio pipeline."
            ),
        ]

        let segmentSets: [[(start: TimeInterval, end: TimeInterval)]] = [
            [(9*3600, 11*3600+1800), (14*3600, 16*3600), (22*3600, 23*3600+2700)],
            [(10*3600, 12*3600+900)],
            [(11*3600, 14*3600+1800)],
            [(9*3600+1800, 11*3600), (13*3600, 15*3600+900), (16*3600, 17*3600)],
            [(8*3600, 10*3600+1800), (15*3600, 16*3600+1800)],
            [(10*3600, 11*3600), (13*3600, 14*3600+2700)],
            [(14*3600, 16*3600+1800), (20*3600, 21*3600+900)],
            [(9*3600, 12*3600)],
            [(11*3600, 12*3600+1800), (14*3600, 15*3600)],
            [(10*3600, 12*3600), (16*3600, 18*3600)],
            [(9*3600, 10*3600+900), (14*3600, 16*3600+1800)],
            [(10*3600+1800, 13*3600), (15*3600, 17*3600)],
            [(20*3600, 21*3600+1800)],
            [(9*3600, 11*3600), (13*3600+1800, 15*3600), (21*3600, 22*3600+2700)],
        ]

        let clamped = min(count, titles.count)
        return (0..<clamped).map { i in
            let date = cal.date(byAdding: .day, value: -i, to: today)!
            let (title, summary) = titles[i]
            let segs = segmentSets[i % segmentSets.count]
            return Episode(
                id: UUID(),
                date: date,
                title: title,
                summary: summary,
                segments: segs
            )
        }
    }
}

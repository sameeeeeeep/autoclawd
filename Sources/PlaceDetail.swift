import Foundation

// MARK: - Activity Type

enum ActivityType: String {
    case location, meeting, transcript, social, personal
}

// MARK: - Place Detail

struct PlaceDetail: Identifiable {
    let id: String
    let name: String
    let icon: String
    let address: String
    var peopleIDs: [String]
    var activityCount: Int

    static func mockPlaces() -> [PlaceDetail] {
        [
            PlaceDetail(
                id: "office",
                name: "Office",
                icon: "\u{1F3E2}",
                address: "WeWork BKC, Mumbai",
                peopleIDs: ["you", "mukul", "priya"],
                activityCount: 24
            ),
            PlaceDetail(
                id: "home",
                name: "Home",
                icon: "\u{1F3E0}",
                address: "Bandra West, Mumbai",
                peopleIDs: ["you"],
                activityCount: 18
            ),
            PlaceDetail(
                id: "cafe",
                name: "Caf\u{00E9}",
                icon: "\u{2615}",
                address: "Third Wave, Linking Rd",
                peopleIDs: ["you", "priya"],
                activityCount: 9
            ),
            PlaceDetail(
                id: "gym",
                name: "Gym",
                icon: "\u{1F4AA}",
                address: "Cult Fit, Pali Hill",
                peopleIDs: ["you"],
                activityCount: 6
            ),
        ]
    }
}

// MARK: - Place Activity

struct PlaceActivity: Identifiable {
    let id = UUID()
    let time: String
    let dayOffset: Int
    let personID: String
    let text: String
    let type: ActivityType
    let project: String?

    static func mockActivities() -> [String: [PlaceActivity]] {
        [
            "office": [
                PlaceActivity(time: "6:43 PM", dayOffset: 0, personID: "you",
                              text: "Dynamic widget architecture sprint",
                              type: .transcript, project: "autoclawd"),
                PlaceActivity(time: "2:00 PM", dayOffset: 0, personID: "mukul",
                              text: "Sustained transcript mode discussion",
                              type: .transcript, project: "autoclawd"),
                PlaceActivity(time: "11:30 AM", dayOffset: 0, personID: "you",
                              text: "Monotone theme design notes",
                              type: .transcript, project: "autoclawd"),
                PlaceActivity(time: "10:00 AM", dayOffset: 0, personID: "mukul",
                              text: "Beta feedback review with Mukul",
                              type: .meeting, project: "trippy"),
                PlaceActivity(time: "9:15 AM", dayOffset: 0, personID: "you",
                              text: "Arrived at office",
                              type: .location, project: nil),
                PlaceActivity(time: "3:30 PM", dayOffset: 1, personID: "you",
                              text: "Y Combinator application session",
                              type: .meeting, project: "autoclawd"),
                PlaceActivity(time: "11:00 AM", dayOffset: 1, personID: "mukul",
                              text: "Sprint planning for API integration",
                              type: .meeting, project: "trippy"),
                PlaceActivity(time: "9:00 AM", dayOffset: 1, personID: "you",
                              text: "Pipeline debugger UI scaffolding",
                              type: .transcript, project: "autoclawd"),
            ],
            "home": [
                PlaceActivity(time: "2:30 AM", dayOffset: 0, personID: "you",
                              text: "Diarization bug debugging session",
                              type: .transcript, project: "autoclawd"),
                PlaceActivity(time: "10:45 PM", dayOffset: 1, personID: "you",
                              text: "Evening journaling & weekly review",
                              type: .personal, project: nil),
                PlaceActivity(time: "8:00 PM", dayOffset: 1, personID: "you",
                              text: "Speaker diarization model fine-tuning",
                              type: .transcript, project: "autoclawd"),
                PlaceActivity(time: "7:30 AM", dayOffset: 0, personID: "you",
                              text: "Morning routine, left for office",
                              type: .location, project: nil),
            ],
            "cafe": [
                PlaceActivity(time: "7:09 PM", dayOffset: 0, personID: "priya",
                              text: "Catch-up conversation with Priya",
                              type: .social, project: nil),
                PlaceActivity(time: "1:00 PM", dayOffset: 0, personID: "you",
                              text: "Flight booking research for Bangalore trip",
                              type: .transcript, project: "personal"),
                PlaceActivity(time: "4:00 PM", dayOffset: 2, personID: "you",
                              text: "Hotword detection brainstorming",
                              type: .transcript, project: "autoclawd"),
                PlaceActivity(time: "2:30 PM", dayOffset: 3, personID: "priya",
                              text: "Influencer outreach planning session",
                              type: .meeting, project: "trippy"),
            ],
            "gym": [
                PlaceActivity(time: "7:00 AM", dayOffset: 1, personID: "you",
                              text: "Morning workout — upper body",
                              type: .personal, project: nil),
                PlaceActivity(time: "6:45 AM", dayOffset: 3, personID: "you",
                              text: "Morning workout — cardio",
                              type: .personal, project: nil),
                PlaceActivity(time: "7:15 AM", dayOffset: 5, personID: "you",
                              text: "Morning workout — legs",
                              type: .personal, project: nil),
            ],
        ]
    }
}

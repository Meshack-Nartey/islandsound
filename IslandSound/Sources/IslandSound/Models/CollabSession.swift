import Foundation

/// Role of the local user within a collab room.
enum CollabRole: String, Codable, Equatable {
    case host
    case guest
}

/// A participant shown in the island's avatar row.
struct Participant: Identifiable, Codable, Equatable {
    var id: String { name }
    let name: String
    let avatar: String // emoji avatar
}

/// Host -> Server -> All Guests, sent every 3 seconds (see CollabEngine).
struct SyncMessage: Codable, Equatable {
    var type: String = "SYNC"
    var trackId: String
    var trackTitle: String
    var artist: String
    var position: Double
    var isPlaying: Bool
    var timestamp: Int64 // Unix ms, used for drift calculation
}

/// Guest -> Server -> Host, sent on a reaction tap.
struct ReactionMessage: Codable, Equatable {
    var type: String = "REACTION"
    var emoji: String
    var from: String
}

/// Server -> All, sent on participant join/leave.
struct ParticipantUpdate: Codable, Equatable {
    var type: String = "PARTICIPANT_UPDATE"
    var participants: [Participant]
}

/// State of an active (or pending) collaborative listening room.
struct CollabSession: Identifiable, Equatable {
    var id: String { code }
    var code: String
    var role: CollabRole
    var participants: [Participant] = []
    var lastSync: SyncMessage?
    var isConnected: Bool = false
    /// Transient reactions to render as floating emoji, most recent last.
    var recentReactions: [ReactionMessage] = []
}

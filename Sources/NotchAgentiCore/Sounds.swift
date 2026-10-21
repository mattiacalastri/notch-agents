import Foundation

// What the notch says with sound. One cue a reading at most, the most urgent wins:
// a question beats a finished turn, a stop beats a terminal opened or closed.
// Two kits: «Sine», synthesized by scripts/sounds_make.py into Sounds/sine/<cue>.wav
// (already levelled per cue), and «Sistema», the sounds macOS ships in
// /System/Library/Sounds, played at a volume per cue.

public enum SoundCue: String, CaseIterable {
    case asking     // a session asks you something: the one that must be heard
    case finished   // a turn is over
    case arrived    // a terminal with Claude opened
    case left       // a terminal closed
    case open       // the blob drops out of the notch
    case close      // the blob goes back in
    case tap        // a click on a tile
}

public enum SoundKit: String, CaseIterable {
    case sine, system, off

    public init(stored: String?) {
        self = stored.flatMap(SoundKit.init(rawValue:)) ?? .sine
    }

    public var label: String {
        switch self {
        case .sine: return "Sine · pulito"
        case .system: return "Sistema · i suoni del Mac"
        case .off: return "Spenti"
        }
    }
}

/// The macOS sound for a cue in the «Sistema» kit, and how loud: a question is heard, a tap barely.
public func systemSound(for cue: SoundCue) -> (name: String, volume: Float) {
    switch cue {
    case .asking: return ("Glass", 0.7)
    case .finished: return ("Ping", 0.5)
    case .arrived: return ("Pop", 0.3)
    case .left: return ("Bottle", 0.25)
    case .open: return ("Tink", 0.15)
    case .close: return ("Tink", 0.1)
    case .tap: return ("Pop", 0.2)
    }
}

/// The cue for the change between two readings, nil when nothing deserves a sound.
/// The first reading (old empty) is silent: launching the app is not news.
public func cueFor(old: [Session], new: [Session]) -> SoundCue? {
    guard !old.isEmpty else { return nil }
    let stopped = justStopped(old: old, new: new)
    if stopped.contains(where: { $0.state == .asking }) { return .asking }
    if !stopped.isEmpty { return .finished }
    let before = Set(old.map(\.tty)), after = Set(new.map(\.tty))
    if !after.subtracting(before).isEmpty { return .arrived }
    if !before.subtracting(after).isEmpty { return .left }
    return nil
}

import AppKit
import SwiftUI
import NotchAgentiCore

// Notch Agenti — the MacBook notch as a window on the Claude Code sessions alive
// in the terminals. Closed: how many sessions work, how many wait for you. Hover:
// a black blob drops out of the notch with one tile per session, the account limits
// and today's tokens. A click on a tile brings that terminal to the front; the two
// buttons open a new Claude Code or Codex session. It never approves anything.

// ── geometry ────────────────────────────────────────────────────────────────
enum Geo {
    static let shoulder: CGFloat = 8       // concave top corners, like the hardware notch
    static let wing: CGFloat = 46          // how far the closed notch grows on each side
    static let openWidth: CGFloat = 520
    static let header: CGFloat = 34
    static let row: CGFloat = 26
    static let maxRows = 8
    static let bottomPad: CGFloat = 14
    static let bottomRadius: CGFloat = 22
    static let tile: CGFloat = 54
    static let tileTall: CGFloat = 80      // with the line of what it does / asks
    static let tileGap: CGFloat = 8
    static let footer: CGFloat = 58        // account + limits under the sessions
    static let codexRow: CGFloat = 54      // second account (Codex) under the first
    static let todayLine: CGFloat = 30
    static let launcher: CGFloat = 40
    static let composer: CGFloat = 112
    static let peekWing: CGFloat = 130
}

struct NotchMetrics {
    let width: CGFloat     // the physical notch
    let height: CGFloat

    static func of(_ screen: NSScreen) -> NotchMetrics {
        let h = screen.safeAreaInsets.top
        if h > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return NotchMetrics(width: screen.frame.width - l.width - r.width, height: h)
        }
        // no notch: a slim pill under the top edge, same behaviour
        return NotchMetrics(width: 180, height: 26)
    }
}

// ── model ───────────────────────────────────────────────────────────────────
final class NotchModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var open = false
    @Published var now = Date()
    @Published var account: Account?
    @Published var usage: Usage?
    /// The Codex (OpenAI) account and its limits, asked live every minute.
    @Published var codex: CodexUsage?
    /// What each session is doing or asking, by tty (from its transcript).
    @Published var details: [String: String] = [:]
    @Published var today: Today?
    /// The session that just stopped for you: the notch peeks out with it for a few seconds.
    @Published var peek: Session?
    @Published var hoverTTY: String?
    /// The engine whose first prompt is being written in the notch; nil = the two launch buttons.
    @Published var composing: Engine?
    @Published var goal = ""
    /// Why the last launch did not start: shown under the buttons, never swallowed.
    @Published var launchError: String?
    var onTap: ((String) -> Void)?
    var onCompose: ((Engine?) -> Void)?
    var onLaunch: (() -> Void)?
    let notch: NotchMetrics

    init(notch: NotchMetrics) { self.notch = notch }

    var summary: Summary { Summary(sessions) }
    var shown: [Session] { Array(sortedForDisplay(sessions).prefix(Geo.maxRows)) }
    var hidden: Int { max(0, sessions.count - Geo.maxRows) }

    var closedSize: CGSize {
        let w = sessions.isEmpty ? notch.width : notch.width + 2 * Geo.wing
        return CGSize(width: w + 2 * Geo.shoulder, height: notch.height)
    }
    var openSize: CGSize {
        let extra: CGFloat = hidden > 0 ? Geo.row : 0
        let lines = (shown.count + 1) / 2
        let body: CGFloat = shown.isEmpty ? Geo.row : CGFloat(lines) * (tileHeight + Geo.tileGap) + 4
        let launch = (composing != nil ? Geo.composer : Geo.launcher) + (launchError != nil ? 16 : 0)
        let footer: CGFloat = (account != nil || usage != nil || codex != nil)
            ? Geo.footer + (codex != nil ? Geo.codexRow : 0) + (today != nil ? Geo.todayLine : 0) : 0
        return CGSize(width: Geo.openWidth + 2 * Geo.shoulder,
                      height: notch.height + Geo.header + body + extra + launch + footer + Geo.bottomPad)
    }
    var tileHeight: CGFloat { shown.contains { details[$0.tty] != nil } ? Geo.tileTall : Geo.tile }
    var peekSize: CGSize {
        CGSize(width: notch.width + 2 * Geo.peekWing + 2 * Geo.shoulder,
               height: notch.height + (peek.flatMap { details[$0.tty] } != nil ? 70 : 50))
    }
    var size: CGSize { open ? openSize : (peek != nil ? peekSize : closedSize) }
}

// ── fixture: NOTCH_AGENTI_FIXTURE=1 shows a busy afternoon, for screenshots ─
enum Fixture {
    static let lines: [String: String] = [
        "t1": "«Preferisci la versione con il grafico o la tabella?»",
        "t2": "«Test verdi, build pronta. La pubblico?»",
        "t3": "modifica main.swift",
        "t4": "legge api.github.com",
        "t5": "Render slide 4 of 9",
    ]

    static let on = ProcessInfo.processInfo.environment["NOTCH_AGENTI_FIXTURE"] == "1"

    static func sessions(now: Date) -> [Session] {
        func s(_ t: String, _ n: String, _ st: SessionState, _ ago: TimeInterval) -> Session {
            Session(tty: t, name: n, state: st, since: now.addingTimeInterval(-ago))
        }
        return [
            s("t1", "report vendite", .asking, 4 * 60),
            s("t2", "deploy sito", .finished, 17 * 60),
            s("t3", "notch app", .working, 20),
            s("t4", "api github", .working, 3 * 60),
            s("t5", "slide corso", .working, 9 * 60),
            s("t6", "dotfiles", .unknown, 5),
        ]
    }
}

// ── shape ───────────────────────────────────────────────────────────────────
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in r: CGRect) -> Path {
        let t = Geo.shoulder, b = min(bottomRadius, (r.height - t) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

enum Tint {
    static let green = Color(red: 0.12, green: 0.95, blue: 0.35)
    static let amber = Color(red: 1.0, green: 0.62, blue: 0.08)
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)   // Claude's terracotta
    static let grey = Color(white: 0.45)
    static let amberText = Color(red: 1, green: 0.72, blue: 0.35)
    static let fresh = Color(red: 0.55, green: 0.76, blue: 1.0)   // a new session, ready for its first message

    static func of(_ s: SessionState) -> Color {
        switch s {
        case .working: return green
        case .asking, .finished: return amber
        case .unknown: return grey
        case .ready: return fresh
        }
    }
}

/// «aspetta te · 4 min» → «4 min»: the tile already says the state by colour.
func shortWait(_ s: Session, now: Date) -> String {
    switch s.state {
    case .unknown: return "in avvio"
    case .ready: return "pronta"
    default: return durationText(seconds: now.timeIntervalSince(s.since))
    }
}

func stateWord(_ s: SessionState) -> String {
    switch s {
    case .asking: return "aspetta te"
    case .finished: return "ha finito"
    case .working: return "lavora"
    case .unknown: return "in avvio"
    case .ready: return "nuova"
    }
}

// ── view ────────────────────────────────────────────────────────────────────
struct NotchView: View {
    @ObservedObject var m: NotchModel
    @FocusState private var goalFocused: Bool

    var body: some View {
        let sz = m.size
        let shape = NotchShape(bottomRadius: m.open ? Geo.bottomRadius : (m.peek != nil ? 18 : 10))
        let peeking = m.peek != nil && !m.open
        // Both contents keep their final layout and the blob clips them while it
        // grows or shrinks: nothing reflows mid-spring and no text spills outside the black.
        ZStack(alignment: .top) {
            closedContent
                .environment(\.animating, false)   // the closed notch is on screen all day: no motion
                .frame(width: m.closedSize.width)
                .opacity(m.open || peeking ? 0 : 1)
                .animation(m.open ? .easeOut(duration: 0.08) : .easeIn(duration: 0.16).delay(0.14), value: m.open)
            openContent
                .environment(\.animating, m.open)
                .frame(width: m.openSize.width, height: m.openSize.height, alignment: .top)
                .opacity(m.open ? 1 : 0)
                .animation(m.open ? .easeOut(duration: 0.2).delay(0.1) : .easeOut(duration: 0.1), value: m.open)
            if let p = m.peek {
                peekContent(p)
                    .frame(width: m.peekSize.width, height: m.peekSize.height, alignment: .top)
                    .opacity(peeking ? 1 : 0)
                    .animation(peeking ? .easeOut(duration: 0.2).delay(0.12) : .easeOut(duration: 0.1), value: peeking)
            }
        }
        .frame(width: sz.width, height: sz.height, alignment: .top)
        .clipShape(shape)
        .background(shape.fill(Color.black).shadow(color: .black.opacity(m.open ? 0.45 : 0), radius: 14, y: 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring(m.open ? Motion.open : Motion.close), value: m.open)
        .animation(.easeInOut(duration: 0.25), value: m.sessions.count)
        .animation(spring(m.peek != nil ? Motion.peekIn : Motion.peekOut), value: m.peek?.tty)
    }

    private func spring(_ s: BlobSpring) -> Animation {
        .spring(response: s.response, dampingFraction: s.damping)
    }

    /// The notch peeks out by itself: who stopped for you, and what it asks.
    private func peekContent(_ s: Session) -> some View {
        let tint = Tint.of(s.state)
        return VStack(spacing: 0) {
            Color.clear.frame(height: m.notch.height)
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(tint, lineWidth: 2.2).frame(width: 28, height: 28)
                        .shadow(color: tint.opacity(0.8), radius: 6)
                    Image(systemName: sessionIcon(for: s.name))
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(s.state == .asking ? "ti ha fatto una domanda" : "ha finito, tocca a te")
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(tint)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 44)
            if let d = m.details[s.tty] {
                Text(d)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 38)
            }
        }
        .padding(.horizontal, Geo.shoulder + 18)
    }

    // ── closed ──
    private var closedContent: some View {
        let sum = m.summary
        return HStack(spacing: 0) {
            if sum.total > 0 {
                HStack(spacing: 6) {
                    Spinner(color: Tint.green, size: 11, line: 2)
                    Text("\(m.sessions.filter { $0.state == .working }.count)").foregroundStyle(.white.opacity(0.92))
                }
                Spacer(minLength: m.notch.width)
                Text("\(sum.waiting)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(sum.waiting > 0 ? .black : .white.opacity(0.5))
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(sum.waiting > 0 ? Tint.amber : Color.white.opacity(0.12)))
                    .shadow(color: sum.waiting > 0 ? Tint.amber.opacity(0.6) : .clear, radius: 4)
            }
        }
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
        .padding(.horizontal, Geo.shoulder + 14)
        .frame(height: m.notch.height)
    }

    // ── open ──
    private var openContent: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: m.notch.height)   // the hardware notch lives here
            header
            if m.sessions.isEmpty { empty } else { grid }
            if m.hidden > 0 {
                Text("+\(m.hidden) \(m.hidden == 1 ? "altra" : "altre")")
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 17)
                    .frame(height: Geo.row)
            }
            launchSection
            if m.account != nil || m.usage != nil || m.codex != nil { footer }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Geo.shoulder + 22)
    }

    /// Big numbers, small words: read in half a second, centred under the notch.
    private var header: some View {
        let sum = m.summary
        return ZStack {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                Counter(n: m.sessions.filter { $0.state == .working }.count, word: "lavorano", color: .white)
                Counter(n: sum.waiting, word: sum.waiting == 1 ? "aspetta te" : "aspettano te",
                        color: sum.waiting > 0 ? Tint.amberText : .white.opacity(0.4))
            }
            HStack {
                Spacer()
                Text(m.now, format: .dateTime.hour().minute())
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(height: Geo.header)
    }

    private var empty: some View {
        Text("Nessuna sessione di Claude Code aperta")
            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.4))
            .frame(height: Geo.row)
    }

    // ── new sessions: a button per engine, the first prompt typed here ──
    private var launchSection: some View {
        VStack(spacing: 0) {
            if let e = m.composing { composer(e) } else { launcher }
            if let err = m.launchError {
                Text(err).font(.system(size: 10)).foregroundStyle(Tint.amberText)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 16)
            }
        }
    }

    private func engineIcon(_ e: Engine) -> some View {
        Image(systemName: e == .claude ? "asterisk" : "chevron.left.forwardslash.chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(e == .claude ? Tint.claude : .white.opacity(0.8))
            .frame(width: 14)
    }

    private var launcher: some View {
        HStack(spacing: 8) {
            ForEach(Engine.allCases, id: \.self) { e in
                Button { m.onCompose?(e) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        engineIcon(e)
                        Text("Lancia \(e.label)").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.07)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: Geo.launcher)
    }

    private func composer(_ e: Engine) -> some View {
        let empty = m.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                engineIcon(e)
                Text("Nuova sessione di \(e.label) · si apre nel terminale")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            }
            TextField("Cosa deve fare? (vuoto = sessione libera)", text: $m.goal, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(2...3)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08)))
                .focused($goalFocused)
                .onAppear { DispatchQueue.main.async { goalFocused = true } }
                .onSubmit { m.onLaunch?() }
            HStack {
                Spacer()
                Button("Annulla") { m.onCompose?(nil) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .keyboardShortcut(.cancelAction)
                Button { m.onLaunch?() } label: {
                    Text(empty ? "Apri" : "Lancia").font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).frame(height: 22)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        .frame(height: Geo.composer, alignment: .top)
    }

    // ── account + limits: one row per account, Claude and (when logged in) Codex ──
    private var footer: some View {
        VStack(spacing: 7) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5).padding(.top, 10)
            accountRow(tag: "CLAUDE", icon: "asterisk", iconTint: Tint.claude, account: m.account,
                       five: m.usage?.fiveHour, seven: m.usage?.sevenDay, readAt: m.usage?.readAt)
            if let c = m.codex {
                Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5).padding(.top, 3)
                accountRow(tag: "CODEX", icon: "chevron.left.forwardslash.chevron.right", iconTint: .white.opacity(0.8),
                           account: c.account, five: c.fiveHour, seven: c.sevenDay, readAt: c.readAt)
            }
            if let t = m.today { todayLine(t) }
        }
        .frame(height: Geo.footer + (m.codex != nil ? Geo.codexRow : 0), alignment: .top)
    }

    private func accountRow(tag: String, icon: String, iconTint: Color, account: Account?,
                            five: LimitWindow?, seven: LimitWindow?, readAt: Date?) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(iconTint)
                    .frame(width: 14)
                Text(tag).font(.system(size: 9, weight: .bold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.4))
                Text(account?.email ?? "account sconosciuto")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1).truncationMode(.middle)
                if let plan = account?.plan, !plan.isEmpty {
                    Text(plan)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(Capsule().fill(.white.opacity(0.8)))
                }
                Spacer(minLength: 6)
                if let r = readAt, m.now.timeIntervalSince(r) > 15 * 60 {
                    Text("letto \(durationText(seconds: m.now.timeIntervalSince(r))) fa")
                        .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                }
            }
            HStack(spacing: 14) {
                Meter(label: "5 ORE", window: five, now: m.now)
                Meter(label: "SETTIMANA", window: seven, now: m.now)
            }
        }
    }

    /// Today's tokens, against yesterday at the same hour, and the last 8 hours.
    private func todayLine(_ t: Today) -> some View {
        HStack(spacing: 8) {
            Text("OGGI").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.4))
            Text(tokensText(t.tokens)).font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            + Text(" token").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            if let d = t.delta {
                Text(d > 0 ? "▲\(d)% su ieri" : (d < 0 ? "▼\(-d)% su ieri" : "come ieri"))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 6)
            let top = max(t.spark.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(t.spark.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 1.2)
                        .fill(i == t.spark.count - 1 ? Tint.green : Color.white.opacity(v > 0 ? 0.45 : 0.12))
                        .frame(width: 5, height: max(2, 16 * CGFloat(v) / CGFloat(top)))
                }
            }
            .frame(height: 16, alignment: .bottom)
            Text("8 h").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.3))
        }
        .padding(.top, 8)
    }

    // ── one tile per session ──
    private var grid: some View {
        let cols = [GridItem(.flexible(), spacing: Geo.tileGap), GridItem(.flexible(), spacing: Geo.tileGap)]
        return LazyVGrid(columns: cols, spacing: Geo.tileGap) {
            ForEach(m.shown) { s in tile(s) }
        }
        .padding(.top, 2)
    }

    private func tile(_ s: Session) -> some View {
        let tint = Tint.of(s.state)
        let waits = s.state.waitsForUser
        let hovered = m.hoverTTY == s.tty
        return HStack(spacing: 10) {
            ZStack {
                if s.state == .working {
                    Spinner(color: tint, size: 30, line: 2.5)
                } else {
                    Circle().stroke(tint.opacity(s.state == .unknown ? 0.4 : 0.9), lineWidth: 2.5)
                        .frame(width: 30, height: 30)
                        .shadow(color: waits ? tint.opacity(0.7) : .clear, radius: 5)
                }
                Image(systemName: sessionIcon(for: s.name))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(s.state == .unknown ? 0.5 : 0.92))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.trailing, 16)   // room for the corner mark, so it never covers the name
                Text(s.state == .unknown ? "in avvio" : "\(stateWord(s.state)) · \(shortWait(s, now: m.now))")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(s.state == .unknown ? .white.opacity(0.4) : tint.opacity(0.9))
                if let d = m.details[s.tty] {
                    Text(d)
                        .font(.system(size: 10.5, weight: waits ? .medium : .regular, design: waits ? .default : .monospaced))
                        .foregroundStyle(.white.opacity(waits ? 0.82 : 0.45))
                        .lineLimit(2).truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(height: m.tileHeight)
        // The «open the terminal» mark sits in the top-right corner as an overlay: it takes no
        // room in the row, so appearing on hover never re-wraps the text under it.
        .overlay(alignment: .topTrailing) {
            if hovered {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hovered ? Color.white.opacity(0.15) : (waits ? tint.opacity(0.10) : Color.white.opacity(0.055)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(hovered ? Color.white.opacity(0.5) : (waits ? tint.opacity(0.45) : Color.white.opacity(0.06)), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(hovered ? 1.025 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onHover { inside in
            if inside { m.hoverTTY = s.tty } else if m.hoverTTY == s.tty { m.hoverTTY = nil }
        }
        .onTapGesture { m.onTap?(s.tty) }
        .help("Apri il terminale")
    }
}

// ── small instruments ───────────────────────────────────────────────────────
struct Counter: View {
    let n: Int, word: String, color: Color
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(n)").font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
            Text(word).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
    }
}

/// Spinners run only where they are seen: a hidden layer still redraws at 60 fps otherwise.
private struct AnimatingKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var animating: Bool {
        get { self[AnimatingKey.self] }
        set { self[AnimatingKey.self] = newValue }
    }
}

/// An arc that turns: the session is working.
struct Spinner: View {
    @Environment(\.animating) private var animating
    let color: Color, size: CGFloat, line: CGFloat
    var body: some View {
        // 20 fps and no blur on the moving arc: cheap enough to sit on the notch all day.
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animating)) { t in
            let a = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: line)
                Circle().trim(from: 0, to: 0.28)
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(a))
            }
        }
        .frame(width: size, height: size)
    }
}

/// How much is left of one limit: the bar empties as the account consumes.
struct Meter: View {
    let label: String, window: LimitWindow?, now: Date
    var body: some View {
        let left = window?.left ?? 0
        let tint: Color = left > 30 ? Tint.green : (left > 10 ? Tint.amber : Color(red: 1, green: 0.27, blue: 0.23))
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(label).font(.system(size: 9, weight: .bold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 4)
                if let w = window {
                    Text("resta \(Int(w.left.rounded()))%").foregroundStyle(tint.opacity(0.95))
                    + Text(" · \(resetText(w.resetsAt, now: now))").foregroundStyle(.white.opacity(0.35))
                } else {
                    Text("—").foregroundStyle(.white.opacity(0.3))
                }
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    if window != nil {
                        Capsule().fill(tint)
                            .frame(width: max(3, g.size.width * left / 100))
                            .shadow(color: tint.opacity(0.5), radius: 3)
                    }
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}

// ── sound: one player, kits chosen from the right-click menu ────────────────
/// Plays the cues of the chosen kit. Only the spacing here: a question or a finished
/// turn at most every 2 s (five sessions stopping together are one sound), the rest every 0.3 s.
final class SoundPlayer {
    private let defaults = UserDefaults.standard
    private var sounds: [SoundCue: NSSound] = [:]
    private var last: [SoundCue: Date] = [:]
    var muted = false   // demo, fixture, pinned open: never a sound

    var kit: SoundKit {
        get { SoundKit(stored: defaults.string(forKey: "soundKit")) }
        set { defaults.set(newValue.rawValue, forKey: "soundKit"); load() }
    }
    /// Opening and closing the blob happen every few seconds: they can be switched off alone.
    var openClose: Bool {
        get { defaults.object(forKey: "soundOpenClose") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "soundOpenClose") }
    }

    init() { load() }

    /// Inside the .app: Contents/Resources/Sounds. Run from .build: the repo's Sounds/.
    static func root() -> URL? {
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Sounds")) }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        dirs.append(exe.deletingLastPathComponent().appendingPathComponent("../../Sounds").standardized)
        dirs.append(exe.deletingLastPathComponent().appendingPathComponent("../../../Sounds").standardized)
        return dirs.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("sine").path) }
    }

    private func load() {
        sounds = [:]
        switch kit {
        case .off:
            return
        case .system:
            for cue in SoundCue.allCases {
                let (name, volume) = systemSound(for: cue)
                // a copy per cue: two cues may share a sound at different volumes
                if let snd = (NSSound(named: NSSound.Name(name))?.copy() as? NSSound) {
                    snd.volume = volume
                    sounds[cue] = snd
                }
            }
        case .sine:
            guard let root = SoundPlayer.root() else { return }
            for cue in SoundCue.allCases {
                let url = root.appendingPathComponent("sine/\(cue.rawValue).wav")
                if let snd = NSSound(contentsOf: url, byReference: true) { sounds[cue] = snd }
            }
        }
    }

    func play(_ cue: SoundCue, force: Bool = false) {
        guard !muted || force, let snd = sounds[cue] else { return }
        if !force, (cue == .open || cue == .close), !openClose { return }
        let gap: TimeInterval = (cue == .asking || cue == .finished) ? 2 : 0.3
        let now = Date()
        if !force, let t = last[cue], now.timeIntervalSince(t) < gap { return }
        // a question silences the plain «finished» of the same moment
        if cue == .finished, let t = last[.asking], now.timeIntervalSince(t) < gap { return }
        last[cue] = now
        snd.stop()
        snd.play()
    }

    /// «Prova i suoni»: every cue of the kit, one after the other.
    func audition() {
        let order: [SoundCue] = [.open, .tap, .close, .arrived, .finished, .asking, .left]
        for (i, cue) in order.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.9) { self.play(cue, force: true) }
        }
    }
}

// ── the panel that sits on the notch ────────────────────────────────────────
final class NotchPanel: NSPanel {
    /// Key only while a prompt is being typed: otherwise the first click on a tile would be eaten.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// The panel is not key: without this the first click on a tile would be eaten.
final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NotchPanel!
    var model: NotchModel!
    var screen: NSScreen!
    var monitors: [Any] = []
    var timer: Timer?
    let reader = DispatchQueue(label: "notch-agenti.reader", qos: .utility)
    let codexReader = DispatchQueue(label: "notch-agenti.codex", qos: .utility)
    /// The first count reads every transcript of the last two days: its own queue, so the sessions never wait for it.
    let tokenReader = DispatchQueue(label: "notch-agenti.tokens", qos: .background)
    var counting = false
    let detailReader = DetailReader()   // touched only on `reader`
    var tokenCounter: TokenCounter!     // touched only on `tokenReader`
    var env = ToolEnv.load()
    let sound = SoundPlayer()

    func applicationDidFinishLaunching(_ n: Notification) {
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
        model = NotchModel(notch: NotchMetrics.of(screen))
        tokenCounter = TokenCounter(root: env.claudeDir.appendingPathComponent("projects"))
        try? FileManager.default.createDirectory(at: defaultRunDir, withIntermediateDirectories: true)

        // Big enough for the tallest open blob; while closed it lets every click through.
        let maxH: CGFloat = 720
        let w = Geo.openWidth + 2 * Geo.shoulder + 60
        let f = screen.frame
        let rect = NSRect(x: f.midX - w / 2, y: f.maxY - maxH, width: w, height: maxH)
        panel = NotchPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        let host = FirstClickHostingView(rootView: NotchView(m: model))
        model.onTap = { [weak self] tty in self?.focusTerminal(tty) }
        model.onCompose = { [weak self] e in self?.compose(e) }
        model.onLaunch = { [weak self] in self?.launch() }
        host.frame = NSRect(origin: .zero, size: rect.size)
        panel.contentView = host
        sound.muted = demo || pinnedOpen || Fixture.on
        let menu = NSMenu()
        menu.delegate = self
        let sounds = NSMenuItem(title: "Suoni", action: nil, keyEquivalent: "")
        sounds.submenu = NSMenu()
        menu.addItem(sounds)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Esci da Notch Agenti", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        host.menu = menu
        panel.orderFrontRegardless()

        refresh()
        if pinnedOpen { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.setOpen(true) } }
        if demo {   // NOTCH_AGENTI_DEMO=1 opens and closes on its own, to film the animation
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.model.open.toggle()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }

        // Hover is read from mouse moves; global monitors for the mouse need no permission.
        let onMove: (NSEvent?) -> Void = { [weak self] _ in self?.hoverCheck() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { onMove($0) }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { onMove($0); return $0 }) { monitors.append(l) }
    }

    /// The blob's rect in screen coordinates (top-centred on the notch).
    func blobRect(_ size: CGSize, margin: CGFloat) -> NSRect {
        let f = screen.frame
        return NSRect(x: f.midX - size.width / 2 - margin, y: f.maxY - size.height - margin,
                      width: size.width + 2 * margin, height: size.height + margin)
    }

    /// NOTCH_AGENTI_OPEN=1 keeps the blob open (screenshots, checks).
    let pinnedOpen = ProcessInfo.processInfo.environment["NOTCH_AGENTI_OPEN"] == "1"
    let demo = ProcessInfo.processInfo.environment["NOTCH_AGENTI_DEMO"] == "1"

    func hoverCheck() {
        if demo { return }
        if pinnedOpen { setOpen(true); return }
        let p = NSEvent.mouseLocation
        if model.open {
            // while a prompt is being typed the notch stays open: the mouse may wander off to think
            if model.composing == nil, !blobRect(model.openSize, margin: 10).contains(p) { setOpen(false) }
        } else if blobRect(model.peek != nil ? model.peekSize : model.closedSize, margin: 2).contains(p) {
            setOpen(true)
        }
    }

    // ── the peek: a session stopped for you ──
    var peekToken = 0

    func showPeek(_ s: Session) {
        guard !model.open, !pinnedOpen, !demo else { return }
        model.peek = s
        peekToken += 1
        let token = peekToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            guard let self, self.peekToken == token else { return }
            self.model.peek = nil
        }
    }

    // ── click: bring that terminal to the front ──
    func focusTerminal(_ tty: String) {
        model.hoverTTY = nil
        sound.play(.tap)
        setOpen(false, quiet: true)
        reader.async {
            let chain = ancestors(ofTTY: tty, in: processes())
            DispatchQueue.main.async {
                guard let app = chain.lazy.compactMap({ NSRunningApplication(processIdentifier: $0) })
                        .first(where: { $0.activationPolicy == .regular }) else { return }
                app.activate()
                if let id = app.bundleIdentifier, let script = tabSelectScript(bundleID: id, tty: tty) {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    p.arguments = ["-e", script]
                    p.standardOutput = FileHandle.nullDevice
                    p.standardError = FileHandle.nullDevice
                    try? p.run()
                }
            }
        }
    }

    // ── a new session: Claude Code or Codex in a new terminal ──
    func compose(_ e: Engine?) {
        model.composing = e
        model.launchError = nil
        if e == nil {
            model.goal = ""
            panel.allowsKey = false
            panel.resignKey()
        } else {
            panel.allowsKey = true
            panel.makeKey()
        }
    }

    func launch() {
        guard let e = model.composing else { return }
        env = ToolEnv.load()
        guard let bin = e == .claude ? env.claude : env.codex else {
            compose(nil)
            model.launchError = "\(e.label) non trovato: installalo e rilancia scripts/install.sh"
            sound.play(.asking)
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let script = launchScript(binary: bin, goal: model.goal, cwd: home, path: env.path)
        let url = defaultRunDir.appendingPathComponent("launch-\(UUID().uuidString).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            model.launchError = "Non partito: \(error.localizedDescription)"
            return
        }
        sound.play(.tap)
        compose(nil)
        setOpen(false, quiet: true)
        NSWorkspace.shared.open(url)
    }

    func setOpen(_ open: Bool, quiet: Bool = false) {
        guard model.open != open else { return }
        if !quiet { sound.play(open ? .open : .close) }
        if open { model.peek = nil; peekToken += 1 } else { model.hoverTTY = nil; if model.composing != nil { compose(nil) } }
        model.open = open
        panel.ignoresMouseEvents = !open
    }

    var ticks = 0

    func refresh() {
        ticks += 1
        if Fixture.on {
            if model.sessions.isEmpty {
                let s = Fixture.sessions(now: Date())
                model.sessions = s
                model.account = Account(email: "tu@esempio.it", plan: "Pro")
                var u = Usage(fiveHour: LimitWindow(used: 38, resetsAt: Date().addingTimeInterval(2 * 3600 + 600)),
                              sevenDay: LimitWindow(used: 11, resetsAt: Date().addingTimeInterval(6 * 86400)))
                u.readAt = Date()
                model.usage = u
                var c = CodexUsage(account: Account(email: "tu@esempio.it", plan: "Plus"),
                                   fiveHour: LimitWindow(used: 12, resetsAt: Date().addingTimeInterval(4 * 3600)),
                                   sevenDay: LimitWindow(used: 1, resetsAt: Date().addingTimeInterval(6 * 86400)))
                c.readAt = Date()
                model.codex = c
                model.details = Fixture.lines
                model.today = Today(tokens: 48_200_000, yesterday: 39_900_000, spark: [27, 137, 218, 131, 60, 18, 9, 30])
                if ProcessInfo.processInfo.environment["NOTCH_AGENTI_PEEK"] == "1" { model.peek = s[0] }
            }
            model.now = Date()
            return
        }
        let wantUsage = ticks % 5 == 1, wantAccount = ticks % 300 == 1, wantToday = ticks % 30 == 1
        if ticks % 60 == 2 {
            // Codex asks OpenAI over the network: its own queue, so a slow answer never delays the sessions.
            codexReader.async { [weak self] in
                guard let c = readCodexUsage() else { return }   // offline or logged out: keep the last reading
                DispatchQueue.main.async { if c != self?.model.codex { self?.model.codex = c } }
            }
        }
        if wantToday, !counting {
            counting = true
            tokenReader.async { [weak self] in
                guard let self else { return }
                let today = self.tokenCounter.read()
                DispatchQueue.main.async {
                    self.counting = false
                    if today != self.model.today { self.model.today = today }
                }
            }
        }
        let env = self.env
        reader.async { [weak self] in
            guard let self else { return }
            let s = snapshot()
            let details = self.detailReader.read(s, runDir: defaultRunDir)
            let u = wantUsage ? readUsage() : nil
            let a = wantAccount ? readAccount(env: env) : nil
            DispatchQueue.main.async {
                let old = self.model.sessions
                let s = carrySince(old: old, new: s)
                if s != old { self.model.sessions = s }
                if details != self.model.details { self.model.details = details }
                if !old.isEmpty, let stopped = justStopped(old: old, new: s).first { self.showPeek(stopped) }
                if let cue = cueFor(old: old, new: s) { self.sound.play(cue) }
                self.model.now = Date()
                if wantUsage, u != self.model.usage { self.model.usage = u }
                if wantAccount, a != self.model.account { self.model.account = a }
            }
        }
    }
}

// ── the «Suoni» submenu, rebuilt each time the menu opens so the ticks are true ──
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let sub = menu.items.first?.submenu else { return }
        sub.removeAllItems()
        for kit in SoundKit.allCases {
            if kit == .off { sub.addItem(.separator()) }
            let item = NSMenuItem(title: kit.label, action: #selector(pickKit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kit.rawValue
            item.state = sound.kit == kit ? .on : .off
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let oc = NSMenuItem(title: "Suono all'apertura e chiusura", action: #selector(toggleOpenClose), keyEquivalent: "")
        oc.target = self
        oc.state = sound.openClose ? .on : .off
        oc.isEnabled = sound.kit != .off
        sub.addItem(oc)
        let test = NSMenuItem(title: "Prova i suoni", action: #selector(audition), keyEquivalent: "")
        test.target = self
        test.isEnabled = sound.kit != .off
        sub.addItem(test)
    }

    @objc func pickKit(_ item: NSMenuItem) {
        sound.kit = SoundKit(stored: item.representedObject as? String)
        if sound.kit != .off { sound.play(.finished, force: true) }   // hear what you picked
    }
    @objc func toggleOpenClose() { sound.openClose.toggle() }
    @objc func audition() { sound.audition() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

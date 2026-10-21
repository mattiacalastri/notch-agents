import Foundation

// The icon of a session, guessed from its name (the project folder, or the title
// the user gave it). First rule that matches wins, so the specific themes sit above
// the generic ones. Words are matched whole: «ui» must not fire inside «quindi».

public let sessionIconFallback = "sparkles"

private let iconRules: [(symbol: String, words: [String])] = [
    ("icloud.and.arrow.up.fill", ["deploy", "rilascio", "release", "pubblica", "publish"]),
    ("checkmark.seal.fill", ["test", "tests", "verifica", "check", "qa"]),
    ("ant.fill", ["bug", "fix", "debug", "errore", "errori", "error"]),
    ("lock.shield.fill", ["sicurezza", "security", "audit", "auth"]),
    ("doc.text.fill", ["docs", "doc", "documentazione", "readme", "note", "notes"]),
    ("envelope.fill", ["email", "mail", "newsletter"]),
    ("bubble.left.fill", ["chat", "bot", "messaggi", "messages"]),
    ("video.fill", ["video", "reel", "reels", "film"]),
    ("photo.fill", ["foto", "immagini", "images", "photo", "design"]),
    ("rectangle.on.rectangle.angled", ["deck", "slide", "slides", "presentazione"]),
    ("chart.bar.fill", ["dati", "data", "analytics", "report", "dashboard", "kpi"]),
    ("cart.fill", ["shop", "shopify", "ecommerce", "negozio", "store"]),
    ("globe", ["sito", "site", "web", "website", "blog", "seo", "landing"]),
    ("iphone", ["ios", "android", "mobile", "app"]),
    ("brain.head.profile", ["ai", "agent", "agents", "agenti", "llm", "ml"]),
    ("server.rack", ["api", "server", "backend", "mcp", "db", "database"]),
    ("paintbrush.pointed.fill", ["ui", "ux", "frontend", "css", "style"]),
    ("graduationcap.fill", ["corso", "lezione", "course", "lesson", "esercizi", "homework"]),
    ("terminal.fill", ["scripts", "script", "cli", "terminale", "terminal", "dotfiles", "config"]),
]

public func sessionIcon(for name: String) -> String {
    let words = Set(name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    for rule in iconRules where rule.words.contains(where: words.contains) {
        return rule.symbol
    }
    return sessionIconFallback
}

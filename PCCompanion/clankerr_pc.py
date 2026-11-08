"""Clankerr PC: lets the Clankerr iPhone app control this Windows PC over your home Wi-Fi.

Trackpad mouse, keyboard typing, media keys and volume, launching apps and games,
lock and sleep. The phone must pair once with a 6-digit code shown on this PC.

Run:  ClankerrPC.exe            (small status window)
      python clankerr_pc.py --console   (no window, log to the terminal)
"""
from __future__ import annotations

import asyncio
import ctypes
import ipaddress
import json
import os
import secrets
import socket
import sys
import threading
import time
from pathlib import Path

import websockets
from pynput.keyboard import Controller as KeyboardController, Key
from pynput.mouse import Button, Controller as MouseController

try:  # Advertise on the network so the phone finds this PC automatically.
    from zeroconf import IPVersion, ServiceInfo, Zeroconf
except Exception:  # pragma: no cover
    Zeroconf = None

PORT = 47815
SERVICE = "_clankerr._tcp.local."
PC_NAME = socket.gethostname()
DATA_DIR = Path(os.environ.get("APPDATA", Path.home())) / "Clankerr"
TOKENS = DATA_DIR / "tokens.json"
CONSOLE = "--console" in sys.argv

mouse = MouseController()
keyboard = KeyboardController()


# ---------------------------------------------------------------- status / UI

class Status:
    """Tiny always-on-top window showing state and pairing codes (or prints with --console)."""

    def __init__(self) -> None:
        self.root = None
        self.label = None
        self.code_label = None
        self.text = "Clankerr PC is running · waiting for your phone"

    def start(self) -> None:
        if CONSOLE:
            print(self.text)
            print("This PC's IP:", lan_ip())
            return
        import tkinter as tk
        try:  # crisp, correctly sized window on 4K / scaled displays
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            pass

        self.root = tk.Tk()
        self.root.title("Clankerr PC")
        self.root.configure(bg="#09081a")
        scale = max(1.0, self.root.winfo_fpixels("1i") / 96.0)
        w, h = int(420 * scale), int(230 * scale)
        x = (self.root.winfo_screenwidth() - w) // 2
        y = (self.root.winfo_screenheight() - h) // 3
        self.root.geometry(f"{w}x{h}+{x}+{y}")
        self.root.minsize(w, h)
        self.root.attributes("-topmost", True)
        self.root.resizable(False, False)
        tk.Label(self.root, text="CLANKERR PC", fg="#ff3d9e", bg="#09081a",
                 font=("Segoe UI", 11, "bold")).pack(pady=(14, 2))
        self.label = tk.Label(self.root, text=self.text, fg="#e8e6f5", bg="#09081a",
                              font=("Segoe UI", 10), wraplength=380)
        self.label.pack()
        self.code_label = tk.Label(self.root, text="", fg="#40e0ff", bg="#09081a",
                                   font=("Segoe UI", 26, "bold"))
        self.code_label.pack(pady=6)
        tk.Label(self.root, text=f"This PC's IP: {lan_ip()}", fg="#8c54ff", bg="#09081a",
                 font=("Segoe UI", 10, "bold")).pack(pady=(0, 8))
        self.root.protocol("WM_DELETE_WINDOW", lambda: os._exit(0))

    def mainloop(self) -> None:
        if self.root is not None:
            self.root.mainloop()
        else:
            while True:
                time.sleep(3600)

    def _ui(self, fn) -> None:
        if self.root is not None:
            self.root.after(0, fn)

    def set(self, text: str) -> None:
        self.text = text
        if CONSOLE:
            print(text)
        self._ui(lambda: self.label.config(text=text))

    def show_code(self, code: str | None) -> None:
        if CONSOLE and code:
            print(f"Clankerr wants to connect — code {code}")

        def apply() -> None:
            self.code_label.config(text=" ".join(code) if code else "")
            if code:
                self.root.deiconify()
                self.root.lift()
                self.root.attributes("-topmost", True)
        self._ui(apply)


status = Status()


# ---------------------------------------------------------------- pairing

def load_tokens() -> dict:
    try:
        return json.loads(TOKENS.read_text())
    except Exception:
        return {}


def save_tokens(tokens: dict) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    TOKENS.write_text(json.dumps(tokens, indent=2))


class Pairing:
    def __init__(self) -> None:
        self.code: str | None = None
        self.code_at = 0.0
        self.attempts: list[float] = []

    def new_code(self) -> str:
        if not self.code or time.time() - self.code_at > 300:
            self.code = f"{secrets.randbelow(1_000_000):06d}"
            self.code_at = time.time()
        status.show_code(self.code)
        return self.code

    def try_code(self, code: str) -> bool:
        now = time.time()
        self.attempts = [t for t in self.attempts if now - t < 60]
        if len(self.attempts) >= 5:
            return False
        self.attempts.append(now)
        ok = bool(self.code) and secrets.compare_digest(str(code), self.code) and now - self.code_at < 300
        if ok:
            self.code = None
            status.show_code(None)
        return ok


pairing = Pairing()


def is_private(host: str) -> bool:
    try:
        ip = ipaddress.ip_address(host.split("%")[0])
        if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        return ip.is_private or ip.is_loopback or ip.is_link_local
    except ValueError:
        return False


# ---------------------------------------------------------------- volume

def _endpoint_volume():
    try:
        from comtypes import CLSCTX_ALL
        from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume
        dev = AudioUtilities.GetSpeakers()
        iface = dev.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        return iface.QueryInterface(IAudioEndpointVolume)
    except Exception:
        return None


def get_volume() -> int | None:
    ev = _endpoint_volume()
    if ev is None:
        return None
    try:
        return round(ev.GetMasterVolumeLevelScalar() * 100)
    except Exception:
        return None


def set_volume(pct: int) -> None:
    ev = _endpoint_volume()
    pct = max(0, min(100, int(pct)))
    if ev is not None:
        try:
            ev.SetMasterVolumeLevelScalar(pct / 100, None)
            if pct > 0:
                ev.SetMute(0, None)
            return
        except Exception:
            pass
    # Fallback: there's no absolute volume without pycaw, so nudge with media keys.
    cur = get_volume() or 50
    key = Key.media_volume_up if pct > cur else Key.media_volume_down
    for _ in range(abs(pct - cur) // 2):
        keyboard.tap(key)


# ---------------------------------------------------------------- apps

SKIP_WORDS = ("uninstall", "help", "readme", "documentation", "website", "release notes",
              "license", "manual", "support", "visit ", "faq", "changelog")


def scan_apps() -> list[dict]:
    """Start Menu shortcuts (all users + you), including Steam game shortcuts."""
    roots = [Path(os.environ.get("ProgramData", r"C:\ProgramData")) / "Microsoft/Windows/Start Menu/Programs",
             Path(os.environ.get("APPDATA", "")) / "Microsoft/Windows/Start Menu/Programs"]
    found: dict[str, dict] = {}
    for root in roots:
        if not root.exists():
            continue
        for p in root.rglob("*"):
            if p.suffix.lower() not in (".lnk", ".url"):
                continue
            name = p.stem
            low = name.lower()
            if any(w in low for w in SKIP_WORDS):
                continue
            found.setdefault(low, {"id": str(p), "name": name})
    builtins = [
        {"id": "steam://open/bigpicture", "name": "Steam Big Picture"},
        {"id": "https://www.netflix.com", "name": "Netflix (browser)"},
        {"id": "https://www.youtube.com", "name": "YouTube (browser)"},
    ]
    for b in builtins:
        found.setdefault(b["name"].lower(), b)
    return sorted(found.values(), key=lambda a: a["name"].lower())


def launch(app_id: str) -> bool:
    allowed = {a["id"] for a in scan_apps()}
    if app_id not in allowed:  # only things we offered, never arbitrary paths
        return False
    os.startfile(app_id)
    return True


# ---------------------------------------------------------------- input

BUTTONS = {"left": Button.left, "right": Button.right, "middle": Button.middle}
KEYS = {
    "enter": Key.enter, "backspace": Key.backspace, "tab": Key.tab, "esc": Key.esc,
    "up": Key.up, "down": Key.down, "left": Key.left, "right": Key.right,
    "home": Key.home, "end": Key.end, "pageup": Key.page_up, "pagedown": Key.page_down,
    "win": Key.cmd, "space": Key.space, "f11": Key.f11, "delete": Key.delete,
}
MODS = {"ctrl": Key.ctrl, "alt": Key.alt, "shift": Key.shift, "win": Key.cmd}
MEDIA = {
    "playpause": Key.media_play_pause, "next": Key.media_next, "prev": Key.media_previous,
    "mute": Key.media_volume_mute, "volup": Key.media_volume_up, "voldown": Key.media_volume_down,
}


def accelerate(d: float) -> float:
    """Slow moves stay precise, fast flicks cover the screen."""
    a = abs(d)
    gain = 1.0 + min(2.5, a / 12.0)
    return d * gain


def press_key(k: str, mods: list[str]) -> None:
    if k == "alt_tab":
        with keyboard.pressed(Key.alt):
            keyboard.tap(Key.tab)
        return
    key = KEYS.get(k)
    if key is None:
        return
    held = [MODS[m] for m in mods if m in MODS]
    for m in held:
        keyboard.press(m)
    try:
        keyboard.tap(key)
    finally:
        for m in reversed(held):
            keyboard.release(m)


def screen(action: str) -> None:
    if action == "lock":
        ctypes.windll.user32.LockWorkStation()
    elif action == "sleep":
        ctypes.windll.powrprof.SetSuspendState(0, 1, 0)
    elif action == "display_off":
        ctypes.windll.user32.SendMessageW(0xFFFF, 0x0112, 0xF170, 2)  # HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, off


# ---------------------------------------------------------------- server

connected: set = set()


async def handle(ws) -> None:
    host = ws.remote_address[0] if ws.remote_address else ""
    if not is_private(host):
        await ws.close(code=4003, reason="private network only")
        return
    tokens = load_tokens()
    authed = False
    device = "phone"

    async def send(obj: dict) -> None:
        await ws.send(json.dumps(obj))

    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
            except ValueError:
                continue
            t = msg.get("t")

            if not authed:
                if t == "hello" and msg.get("token") and msg["token"] in tokens:
                    authed = True
                    device = tokens[msg["token"]].get("device", device)
                elif t == "pair":
                    if pairing.try_code(str(msg.get("code", ""))):
                        token = secrets.token_hex(32)
                        device = str(msg.get("device", "phone"))[:60]
                        tokens[token] = {"device": device, "since": int(time.time())}
                        save_tokens(tokens)
                        authed = True
                        await send({"t": "paired", "token": token})
                    else:
                        await send({"t": "badcode"})
                        continue
                else:
                    pairing.new_code()
                    await send({"t": "needcode", "name": PC_NAME})
                    continue
                connected.add(ws)
                status.set(f"Clankerr PC is running · {device} connected")
                await send({"t": "info", "name": PC_NAME, "volume": get_volume()})
                continue

            # Authenticated commands
            if t == "move":
                mouse.move(accelerate(float(msg.get("dx", 0))), accelerate(float(msg.get("dy", 0))))
            elif t == "click":
                b = BUTTONS.get(msg.get("button", "left"), Button.left)
                mouse.click(b, 2 if msg.get("double") else 1)
            elif t == "down":
                mouse.press(BUTTONS.get(msg.get("button", "left"), Button.left))
            elif t == "up":
                mouse.release(BUTTONS.get(msg.get("button", "left"), Button.left))
            elif t == "scroll":
                mouse.scroll(float(msg.get("dx", 0)), float(msg.get("dy", 0)))
            elif t == "text":
                keyboard.type(str(msg.get("s", ""))[:500])
            elif t == "key":
                press_key(str(msg.get("k", "")), list(msg.get("mods") or []))
            elif t == "media":
                a = msg.get("a")
                if a == "stop":
                    keyboard.tap(Key.media_play_pause)
                elif a in MEDIA:
                    keyboard.tap(MEDIA[a])
                if a in ("mute", "volup", "voldown"):
                    await send({"t": "volume", "volume": get_volume()})
            elif t == "volume":
                if "set" in msg:
                    set_volume(int(msg["set"]))
                await send({"t": "volume", "volume": get_volume()})
            elif t == "apps":
                await send({"t": "apps", "apps": scan_apps()})
            elif t == "launch":
                ok = launch(str(msg.get("id", "")))
                await send({"t": "launched", "ok": ok})
            elif t == "screen":
                screen(str(msg.get("action", "")))
            elif t == "info":
                await send({"t": "info", "name": PC_NAME, "volume": get_volume()})
            elif t == "ping":
                await send({"t": "pong"})
    except websockets.ConnectionClosed:
        pass
    finally:
        connected.discard(ws)
        if not connected:
            status.set("Clankerr PC is running · waiting for your phone")


def lan_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("8.8.8.8", 80))  # no packets sent; just picks the LAN interface
            return s.getsockname()[0]
        finally:
            s.close()
    except Exception:
        return socket.gethostbyname(socket.gethostname())


def advertise():
    if Zeroconf is None:
        return None
    try:
        ip = socket.gethostbyname(socket.gethostname())
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("8.8.8.8", 80))  # no packets sent; just picks the LAN interface
            ip = s.getsockname()[0]
        finally:
            s.close()
        info = ServiceInfo(SERVICE, f"{PC_NAME}.{SERVICE}", addresses=[socket.inet_aton(ip)],
                           port=PORT, properties={"name": PC_NAME}, server=f"{PC_NAME}.local.")
        zc = Zeroconf(ip_version=IPVersion.V4Only)
        zc.register_service(info)
        return zc
    except Exception as e:
        print("Could not advertise on the network:", e)
        return None


async def serve() -> None:
    advertise()
    async with websockets.serve(handle, "0.0.0.0", PORT, max_size=64_000, ping_interval=20):
        await asyncio.Future()


def main() -> None:
    status.start()
    threading.Thread(target=lambda: asyncio.run(serve()), daemon=True).start()
    status.mainloop()


if __name__ == "__main__":
    main()

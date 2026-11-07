Warning: truncated output (original token count: 24517)
Total output lines: 1899

from __future__ import annotations

import ctypes
import ctypes.wintypes
import base64
import hashlib
import http.server
import json
import os
import queue
import secrets
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import webbrowser
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

try:
    import pystray
    from PIL import Image, ImageDraw, ImageFont
except Exception:  # Tray support is optional when running directly from source.
    pystray = None
    Image = ImageDraw = ImageFont = None

APP_NAME = "NOVA Copilot"
APP_VERSION = "1.5.2"
CHAT_URL = "https://nova-copilot-gateway.vercel.app/api/chat"
SUPABASE_URL = "https://nhzpodixkjhynvcwnzok.supabase.co"
SUPABASE_PUBLISHABLE_KEY = "sb_publishable_LqyBAJMOMir72jmLcziX_A_wArHa_L0"
GOOGLE_OAUTH_REDIRECT_URI = "http://127.0.0.1:8765/oauth/callback"
GITHUB_RELEASES_URL = "https://api.github.com/repos/Ethan-cat-a/NOVA/releases?per_page=100"
HOTKEY_LABEL = "Ctrl + Shift + Space"
CONTEXT_LIMIT = 15_000

BG = "#F5F7FB"
WHITE = "#FFFFFF"
INK = "#172033"
MUTED = "#667085"
BORDER = "#E2E7F0"
ACCENT = "#2857C5"
ACCENT_LIGHT = "#EAF0FF"
GREEN = "#219653"
ORANGE = "#D88724"
USER_BUBBLE = "#2857C5"

MOD_CONTROL = 0x0002
MOD_SHIFT = 0x0004
VK_SPACE = 0x20
WM_HOTKEY = 0x0312
WM_QUIT = 0x0012
HOTKEY_ID = 0x4E4F

MODE_INSTRUCTIONS = {
    "Fast": "Answer quickly and directly. Keep the answer concise, prioritize the most useful result first, and avoid unnecessary background or long explanations.",
    "Hard Thinker": "Take extra time to analyze the task carefully. Check assumptions, reason through important steps, consider alternatives and edge cases, and verify calculations when possible. Present the conclusion and key rationale clearly without exposing private chain-of-thought.",
    "Coding": "Act as a senior software engineer. Provide practical, runnable code when appropriate, with sensible defaults, clear structure, and robust error handling. For debugging, identify the likely root cause and give corrected code. Include concise setup or usage notes and avoid pseudocode unless requested.",
}


class _DataBlob(ctypes.Structure):
    _fields_ = [("cbData", ctypes.wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.wintypes.BYTE))]


def _dpapi(data: bytes, *, protect: bool) -> bytes:
    input_buffer = ctypes.create_string_buffer(data)
    input_blob = _DataBlob(len(data), ctypes.cast(input_buffer, ctypes.POINTER(ctypes.wintypes.BYTE)))
    output_blob = _DataBlob()
    crypt32 = ctypes.windll.crypt32
    crypt = crypt32.CryptProtectData if protect else crypt32.CryptUnprotectData
    crypt.restype = ctypes.wintypes.BOOL
    if protect:
        crypt.argtypes = [ctypes.POINTER(_DataBlob), ctypes.wintypes.LPCWSTR, ctypes.POINTER(_DataBlob), ctypes.wintypes.LPVOID, ctypes.wintypes.LPVOID, ctypes.wintypes.DWORD, ctypes.POINTER(_DataBlob)]
        ok = crypt(ctypes.byref(input_blob), "NOVA Copilot account session", None, None, None, 1, ctypes.byref(output_blob))
    else:
        crypt.argtypes = [ctypes.POINTER(_DataBlob), ctypes.POINTER(ctypes.wintypes.LPWSTR), ctypes.POINTER(_DataBlob), ctypes.wintypes.LPVOID, ctypes.wintypes.LPVOID, ctypes.wintypes.DWORD, ctypes.POINTER(_DataBlob)]
        ok = crypt(ctypes.byref(input_blob), None, None, None, None, 1, ctypes.byref(output_blob))
    if not ok:
        raise OSError(ctypes.get_last_error(), "Windows could not protect the NOVA account session.")
    try:
        return ctypes.string_at(output_blob.pbData, output_blob.cbData)
    finally:
        local_free = ctypes.windll.kernel32.LocalFree
        local_free.argtypes = [ctypes.c_void_p]
        local_free.restype = ctypes.c_void_p
        local_free(ctypes.cast(output_blob.pbData, ctypes.c_void_p))


def _auth_session_path() -> Path:
    local_app_data = os.environ.get("LOCALAPPDATA") or str(Path.home() / "AppData" / "Local")
    return Path(local_app_data) / APP_NAME / "account-session.dat"


class ActiveRequest:
    """Tracks one network request and safely closes its response on cancel."""

    def __init__(self, message_id: str):
        self.message_id = message_id
        self.cancelled = threading.Event()
        self._lock = threading.Lock()
        self._response = None

    def attach_response(self, response: Any) -> bool:
        with self._lock:
            cancelled = self.cancelled.is_set()
            if not cancelled:
                self._response = response
        if cancelled:
            self._close(response)
            return False
        return True

    def clear_response(self, response: Any) -> None:
        with self._lock:
            if self._response is response:
                self._response = None

    def cancel(self) -> None:
        self.cancelled.set()
        with self._lock:
            response = self._response
            self._response = None
        if response is not None:
            self._close(response)

    @staticmethod
    def _close(response: Any) -> None:
        try:
            response.close()
        except Exception:
            pass


def app_data_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA") or str(Path.home())
    path = Path(base) / "NOVA Copilot"
    path.mkdir(parents=True, exist_ok=True)
    return path


DATA_FILE = app_data_dir() / "threads.json"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def new_thread() -> dict[str, Any]:
    return {
        "id": str(uuid.uuid4()),
        "title": "New chat",
        "mode": "Fast",
        "word_doc_mode": False,
        "messages": [],
        "updated_at": utc_now(),
    }


def load_threads() -> list[dict[str, Any]]:
    try:
        raw = json.loads(DATA_FILE.read_text(encoding="utf-8"))
        if not isinstance(raw, list):
            raise ValueError("Chat history is not a list")
        valid = []
        for item in raw:
            if not isinstance(item, dict) or not isinstance(item.get("messages"), list):
                continue
            item.setdefault("id", str(uuid.uuid4()))
            item.setdefault("title", "New chat")
            item.setdefault("mode", "Fast")
            item.setdefault("word_doc_mode", False)
            item.setdefault("updated_at", utc_now())
            if item["mode"] not in MODE_INSTRUCTIONS:
                item["mode"] = "Fast"
            valid.append(item)
        return sorted(valid, key=lambda x: x.get("updated_at", ""), reverse=True) or [new_thread()]
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return [new_thread()]


def save_threads(threads: list[dict[str, Any]]) -> None:
    try:
        DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
        temp = DATA_FILE.with_suffix(".tmp")
        temp.write_text(json.dumps(threads[:40], ensure_ascii=False, indent=2), encoding="utf-8")
        temp.replace(DATA_FILE)
    except OSError:
        # A failed local save should not interrupt an active response.
        pass


class WindowsHotkey:
    """Registers Ctrl+Shift+Space on a dedicated Win32 message thread."""

    def __init__(self, callback_queue: queue.Queue[str]):
        self.callback_queue = callback_queue
        self.thread: threading.Thread | None = None
        self.thread_id: int | None = None
        self.registered = False
        self._stop = threading.Event()

    def start(self) -> None:
        if os.name != "nt":
            return
        self.thread = threading.Thread(target=self._message_loop, name="NOVA-Hotkey", daemon=True)
        self.thread.start()

    def _message_loop(self) -> None:
        user32 = ctypes.windll.user32
        kernel32 = ctypes.windll.kernel32
        self.thread_id = kernel32.GetCurrentThreadId()
        msg = ctypes.wintypes.MSG()
        # Force creation of this thread's message queue before another thread posts WM_QUIT.
        user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, 0)
        self.registered = bool(user32.RegisterHotKey(None, HOTKEY_ID, MOD_CONTROL | MOD_SHIFT, VK_SPACE))
        while not self._stop.is_set():
            result = user32.GetMessageW(ctypes.byref(msg), None, 0, 0)
            if result <= 0:
                break
            if msg.message == WM_HOTKEY and msg.wParam == HOTKEY_ID:
                self.callback_queue.put("toggle")
        if self.registered:
            user32.UnregisterHotKey(None, HOTKEY_ID)
            self.registered = False

    def stop(self) -> None:
        self._stop.set()
        if os.name == "nt" and self.thread_id:
            ctypes.windll.user32.PostThreadMessageW(self.thread_id, WM_QUIT, 0, 0)


class NovaCopilotApp:
    def __init__(self) -> None:
        if os.name != "nt":
            raise RuntimeError("This build is intended for Windows 10/11.")

        self.root = tk.Tk()
        self.root.title(APP_NAME)
        self.root.geometry("430x700")
        self.root.minsize(370, 520)
        self.root.update_idletasks()
        screen_w = self.root.winfo_screenwidth()
        self.root.geometry(f"430x700+{max(0, screen_w - 448)}+30")
        self.root.configure(bg=BG)
        self.root.protocol("WM_DELETE_WINDOW", self.hide_panel)
        self.root.option_add("*Font", "Segoe UI 10")

        self.threads = load_threads()
        self.auth_session = self._load_auth_session()
        self.is_owner = False
        self.active_thread_id = self.threads[0]["id"]
        self.is_sending = False
        self.active_request: ActiveRequest | None = None
        self.events: queue.Queue[tuple[str, Any]] = queue.Queue()
        self.hotkey_events: queue.Queue[str] = queue.Queue()
        self.hotkey = WindowsHotkey(self.hotkey_events)
        self.hotkey_status = "Registering shortcut…"
        self.connected = False
        self.connection_status = "Connecting to Nova…"
        self.pinned = True
        self.launch_at_login = self._is_launch_at_login()
        self.tray_icon = None
        self.tray_thread: threading.Thread | None = None
        self.edge_window: tk.Toplevel | None = None
        self._closing = False
        self._last_save = 0.0
        self.message_labels: dict[str, tk.Label] = {}
        self.pending_context: dict[str, dict[str, str]] = {}
        self._writing_message_ids: set[str] = set()
        self._update_check_running = False
        self._account_auth_pending = False
        self._account_window: tk.Toplevel | None = None
        self._account_status_label: tk.Label | None = None
        self._account_submit_button: tk.Button | None = None
        self._account_google_button: tk.Button | None = None
        self._account_email_entry: tk.Entry | None = None
        self._account_signin_frame: tk.Frame | None = None
        self._account_signin_toggle_button: tk.Button | None = None
        self._account_identity_label: tk.Label | None = None
        self._account_plan_label: tk.Label | None = None
        self._owner_section: tk.Frame | None = None

        self._configure_styles()
        self._build_ui()
        self._create_edge_handle()
        self.hotkey.start()
        self._start_tray()
        self.root.after(100, self._poll_events)
        self.root.after(250, self._poll_hotkey)
        self.root.after(350, self.check_connection)
        self.root.after(700, self._report_hotkey_status)

    @property
    def current_thread(self) -> dict[str, Any]:
        for thread in self.threads:
            if thread["id"] == self.active_thread_id:
                return thread
        if not self.threads:
            self.threads = [new_thread()]
        self.active_thread_id = self.threads[0]["id"]
        return self.threads[0]

    def _load_auth_session(self) -> dict[str, Any] | None:
        path = _auth_session_path()
        try:
            data = json.loads(_dpapi(path.read_bytes(), protect=False).decode("utf-8"))
            if data.get("access_token") and data.get("refresh_token") and (data.get("email") or data.get("is_anonymous")):
                return data
        except (OSError, ValueError, json.JSONDecodeError):
            pass
        return None

    def _save_auth_session(self, session: dict[str, Any]) -> None:
        path = _auth_session_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        protected = _dpapi(json.dumps(session, separators=(",", ":")).encode("utf-8"), protect=True)
        path.write_bytes(protected)

    def _clear_auth_session(self) -> None:
        self.auth_session = None
        self.is_owner = False
        try:
            _auth_session_path().unlink(missing_ok=True)
        except OSError:
            pass
        self.root.after(0, self._refresh_account_button)

    @staticmethod
    def _supabase_auth_request(path: str, payload: dict[str, Any]) -> dict[str, Any]:
        request = urllib.request.Request(
            SUPABASE_URL + path,
            data=json.dumps(payload).encode("utf-8"),
            headers={"apikey": SUPABASE_PUBLISHABLE_KEY, "Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                return json.loads(response.read(256 * 1024).decode("utf-8", "replace"))
        except urllib.error.HTTPError as exc:
            try:
                details = json.loads(exc.read(32 * 1024).decode("utf-8", "replace"))
                message = details.get("message") or details.get("msg") or details.get("error_description") or details.get("error")
            except Exception:
                message = None
            raise RuntimeError(str(message or f"Account request failed (HTTP {exc.code}).")) from None

    def _create_guest_session(self) -> str:
        result = self._supabase_auth_request("/auth/v1/signup", {"data": {}})
        if not result.get("access_token") or not result.get("refresh_token"):
            raise RuntimeError("NOVA couldn’t start a guest profile. Try again or sign in.")
        user = result.get("user") or {}
        if user.get("is_anonymous") is False:
            raise RuntimeError("NOVA could not verify the guest profile. Try again or sign in.")
        session = {
            "access_token": result["access_token"],
            "refresh_token": result["refresh_token"],
            "expires_at": result.get("expires_at") or time.time() + int(result.get("expires_in", 3600)),
            "email": user.get("email"),
            "is_anonymous": True,
        }
        self._save_auth_session(session)
        self.auth_session = session
        self.events.put(("auth-session", session))
        return str(session["access_token"])

    def _get_access_token(self) -> str:
        session = self.auth_session
        if not session:
            return self._create_guest_session()
        if float(session.get("expires_at", 0)) > time.time() + 60:
            return str(session["access_token"])
        try:
            refreshed = self._supabase_auth_request("/auth/v1/token?grant_type=refresh_token", {"refresh_token": session["refresh_token"]})
            if not refreshed.get("access_token") or not refreshed.get("refresh_token"):
                raise RuntimeError("Session refresh did not return an access token.")
            updated = {
                "access_token": refreshed["access_token"],
                "refresh_token": refreshed["refresh_token"],
                "expires_at": refreshed.get("expires_at") or time.time() + int(refreshed.get("expires_in", 3600)),
                "email": (refreshed.get("user") or {}).get("email") or session.get("email"),
                "is_anonymous": (refreshed.get("user") or {}).get("is_anonymous", session.get("is_anonymous", False)),
            }
            self._save_auth_session(updated)
            self.events.put(("auth-session", updated))
            return str(updated["access_token"])
        except Exception:
            was_guest = bool(session.get("is_anonymous"))
            self._clear_auth_session()
            self.events.put(("auth-expired", None))
            if was_guest:
                return self._create_guest_session()
            raise RuntimeError("Your NOVA session expired. Sign in again from Account.") from None

    def _supabase_rpc(self, name: str, payload: dict[str, Any], token: str) -> Any:
        request = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/rpc/{name}",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "apikey": SUPABASE_PUBLISHABLE_KEY,
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                return json.loads(response.read(64 * 1024).decode("utf-8", "replace"))
        except Exception as exc:
            raise RuntimeError("NOVA couldn’t reach the owner profile service. Try again.") from exc

    def _refresh_account_button(self) -> None:
        if not hasattr(self, "account_button"):
            return
        self.account_button.configure(text="Account" if self.auth_session else "Sign in")

    def open_account(self) -> None:
        if self._account_window and self._account_window.winfo_exists():
            self._account_window.lift()
            return

        window = tk.Toplevel(self.root)
        self._account_window = window
        window.title("NOVA Account")
        window.transient(self.root)
        window.resizable(False, False)
        window.configure(bg=WHITE)
        window.protocol("WM_DELETE_WINDOW", lambda: self._close_account_window(window))
        body = tk.Frame(window, bg=WHITE, padx=18, pady=16)
        body.pack(fill="both", expand=True)
        tk.Label(body, text="NOVA Account", bg=WHITE, fg=INK, font=("Segoe UI Semibold", 14), anchor="w").pack(fill="x")
        tk.Label(body, text="Sign-in is optional · 25 messages per day", bg=WHITE, fg=MUTED, font=("Segoe UI", 9), anchor="w").pack(fill="x", pady=(2, 10))

        session = self.auth_session
        self._account_identity_label = tk.Label(
            body,
            text=("This device’s guest profile" if session and session.get("is_anonymous") else str((session or {}).get("email") or "")),
            bg=WHITE, fg=INK, font=("Segoe UI", 10, "bold"), anchor="w"
        )
        if session:
            self._account_identity_label.pack(fill="x", pady=(0, 5))
            self._account_plan_label = tk.Label(body, text="25 messages per UTC day", bg=WHITE, fg=ACCENT, font=("Segoe UI", 9, "bold"), anchor="w")
            self._account_plan_label.pack(fill="x")
            tk.Label(body, text="Your daily allowance resets at 00:00 UTC.", bg=WHITE, fg=MUTED, font=("Segoe UI", 8), anchor="w").pack(fill="x", pady=(5, 10))
        else:
            self._account_plan_label = None
            tk.Label(body, text="Chat as a guest; NOVA creates a device profile automatically. You can also sign in to an existing account.", bg=WHITE, fg=MUTED, font=("Segoe UI", 8), wraplength=320, justify="left", anchor="w").pack(fill="x", pady=(0, 10))

        self._owner_code_var = tk.StringVar()
        self._owner_section = tk.Frame(body, bg=WHITE)
        self._owner_section.pack(fill="x")
        tk.Label(self._owner_section, text="OWNER PROFILE", bg=WHITE, fg=MUTED, font=("Segoe UI", 8, "bold"), anchor="w").pack(fill="x")
        owner_row = tk.Frame(self._owner_section, bg=WHITE)
        owner_row.pack(fill="x", pady=(3, 5))
        self._owner_code_entry = tk.Entry(owner_row, textvariable=self._owner_code_var, show="•", font=("Segoe UI", 9), relief="solid", bd=1)
        self._owner_code_entry.pack(side="left", fill="x", expand=True)
        self._owner_redeem_button = tk.Button(owner_row, text="Activate", command=self._redeem_owner_code, padx=8, pady=4)
        self._owner_redeem_button.pack(side="left", padx=(6, 0))
        self._account_status_label = tk.Label(body, text="", bg=WHITE, fg=ACCENT, font=("Segoe UI", 8), wraplength=320, justify="left", anchor="w")
        self._account_status_label.pack(fill="x", pady=(0, 8))

        if session:
            button_row = tk.Frame(body, bg=WHITE)
            button_row.pack(fill="x", pady=(2, 0))
            tk.Button(button_row, text="Done", command=lambda: self._close_account_window(window), padx=12, pady=5).pack(side="right")
            if not session.get("is_anonymous"):
                tk.Button(button_row, text="Sign out", command=lambda: self._sign_out(window), padx=12, pady=5).pack(side="right", padx=(0, 6))
            elif not self.is_owner:
                self._account_signin_toggle_button = tk.Button(body, text="Sign in to an existing account…", command=self._toggle_account_signin, padx=10, pady=5)
                self._account_signin_toggle_button.pack(fill="x", pady=(8, 0))
                self._owner_status_pending = True
                self._account_signin_toggle_button.configure(state="disabled")
                self._account_signin_frame = self._build_existing_signin_controls(body)
                self._account_signin_frame.pack_forget()
            threading.Thread(target=self._owner_status_worker, daemon=True).start()
        else:
            ttk.Separator(body, orient="horizontal").pack(fill="x", pady=(4, 8))
            self._account_signin_frame = self._build_existing_signin_controls(body)
            self._account_signin_frame.pack(fill="x")
            if self._account_email_entry:
                self._account_email_entry.focus_set()
        window.update_idletasks()
        window.geometry(f"360x{window.winfo_reqheight()}")
        window.grab_set()

    def _build_existing_signin_controls(self, parent: tk.Widget) -> tk.Frame:
        frame = tk.Frame(parent, bg=WHITE)
        email_var = tk.StringVar()
        password_var = tk.StringVar()
        google_button = tk.Button(frame, text="Continue with Google", command=self._start_google_sign_in, bg=WHITE, fg=INK, relief="solid", bd=1, padx=12, pady=7)
        google_button.pack(fill="x", pady=(0, 8))
        self._account_google_button = google_button
        tk.Label(frame, text="Use the Google identity linked to your existing NOVA account, or enter its credentials.", bg=WHITE, fg=MUTED, font=("Segoe UI", 8), wraplength=320, justify="left", anchor="w").pack(fill="x", pady=(0, 7))
        tk.Label(frame, text="Email address", bg=WHITE, fg=MUTED, font=("Segoe UI", 8), anchor="w").pack(fill="x")
        email_entry = tk.Entry(frame, textvariable=email_var, font=("Segoe UI", 10), relief="solid", bd=1)
        email_entry.pack(fill="x", pady=(3, 7))
        tk.Label(frame, text="Password", bg=WHITE, fg=MUTED, font=("Segoe UI", 8), anchor="w").pack(fill="x")
        password_entry = tk.Entry(frame, textvariable=password_var, show="•", font=("Segoe UI", 10), relief="solid", bd=1)
        password_entry.pack(fill="x", pady=(3, 4))
        tk.Label(frame, text="Optional sign-in to an existing account. Account creation isn’t available here.", bg=WHITE, fg=MUTED, font=("Segoe UI", 8), wraplength=320, justify="left", anchor="w").pack(fill="x", pady=(2, 6))
        submit_button = tk.Button(frame, text="Sign in", bg=ACCENT, fg=WHITE, relief="flat", padx=12, pady=5)
        submit_button.pack(anchor="e")
        self._account_submit_button = submit_button
        self._account_email_entry = email_entry

        def submit() -> None:
            email = email_var.get().strip().lower()
            password = password_var.get()
            if not email or not password:
                self._account_status_label.configure(text="Enter your email and password.", fg=ORANGE)
                return
            if self._account_auth_pending:
                return
            self._account_auth_pending = True
            submit_button.configure(text="Working…", state="disabled")
            if self._account_google_button and self._account_google_button.winfo_exists():
                self._account_google_button.configure(state="disabled")
            self._account_status_label.configure(text="Contacting the sign-in service…", fg=MUTED)
            threading.Thread(target=self._account_auth_worker, args=(email, password), daemon=True).start()

        submit_button.configure(command=submit)
        password_entry.bind("<Return>", lambda _event: submit())
        return frame

    def _toggle_account_signin(self) -> None:
        frame = self._account_signin_frame
        button = self._account_signin_toggle_button
        if not frame or not button or self._owner_status_pending or self.is_owner:
            return
        if frame.winfo_manager():
            frame.pack_forget()
            button.configure(text="Sign in to an existing account…")
        else:
            frame.pack(fill="x", pady=(6, 0))
            button.configure(text="Hide sign-in options")

    def _owner_status_worker(self) -> None:
        try:
            token = self._get_access_token()
            is_owner = self._supabase_rpc("nova_copilot_owner_status", {}, token) is True
            self.events.put(("owner-status", is_owner))
        except Exception:
            self.events.put(("owner-status", False))

    def _redeem_owner_code(self) -> None:
        code = self._owner_code_var.get().strip()
        if len(code) < 20 or getattr(self, "_owner_redeem_pending", False):
            if len(code) < 20:
                self._account_status_label.configure(text="Enter the full owner access code.", fg=ORANGE)
            return
        self._owner_redeem_pending = True
        self._owner_redeem_button.configure(text="Working…", state="disabled")
        self._account_status_label.configure(text="Checking the one-time owner code…", fg=MUTED)
        threading.Thread(target=self._owner_redeem_worker, args=(code,), daemon=True).start()

    def _owner_redeem_worker(self, code: str) -> None:
        try:
            token = self._get_access_token()
            result = self._supabase_rpc("nova_copilot_redeem_owner_code", {"p_code": code}, token)
            self.events.put(("owner-redeem", (bool(isinstance(result, dict) and result.get("is_owner") is True), None)))
        except Exception as exc:
            self.events.put(("owner-redeem", (False, str(exc))))

    def _account_auth_worker(self, email: str, password: str) -> None:
        try:
            result = self._supabase_auth_request("/auth/v1/token?grant_type=password", {"email": email, "password": password})
            if not result.get("access_token") or not result.get("refresh_token"):
                raise RuntimeError("Sign-in did not return a session. Verify your email and try again.")
            user = result.get("user") or {}
            if not (user.get("email_confirmed_at") or user.get("confirmed_at")):
                raise RuntimeError("Verify your email before signing in to NOVA Copilot.")
            session = {
                "access_token": result["access_token"],
                "refresh_token": result["refresh_token"],
                "expires_at": result.get("expires_at") or time.time() + int(result.get("expires_in", 3600)),
                "email": user.get("email") or email,
                "is_anonymous": bool(user.get("is_anonymous", False)),
            }
            self.events.put(("account-auth", (session, "", None)))
        except Exception as exc:
            self.events.put(("account-auth", (None, "", str(exc))))

    def _start_google_sign_in(self) -> None:
        if self._account_auth_pending:
            return
        self._account_auth_pending = True
        if self._account_google_button and self._account_google_button.winfo_exists():
            self._account_google_button.configure(text="Waiting for Google…", state="disabled")
        if self._account_submit_button and self._account_submit_button.winfo_exists():
            self._account_submit_button.configure(state="disabled")
        if self._account_status_label and self._account_status_label.winfo_exists():
            self._account_status_label.configure(text="Opening Google in your browser…", fg=MUTED)
        threading.Thread(target=self._google_auth_worker, daemon=True).start()

    def _google_auth_worker(self) -> None:
        class OAuthCallbackHandler(http.server.BaseHTTPRequestHandler):
            server_version = "NOVAAuth"
            sys_version = ""

            def log_message(self, _format: str, *_args: Any) -> None:
                # Never log callback URLs because they contain short-lived auth codes.
                return

            def do_GET(self) -> None:
                parsed = urllib.parse.urlparse(self.path)
                if parsed.path != "/oauth/callback":
                    self.send_error(404)
                    return
                params = urllib.parse.parse_qs(parsed.query)
                code = (params.get("code") or [""])[0]
                error = (params.get("error_description") or params.get("error") or [""])[0]
                if code:
                    self.server.oauth_result = {"code": code}
                    page = "Google sign-in complete. You can return to NOVA Copilot."
                    status = 200
                elif error:
                    self.server.oauth_result = {"error": error}
                    page = "Google sign-in was not completed. Return to NOVA Copilot and try again."
                    status = 200
                else:
                    self.server.oauth_result = {"error": "Google did not return a sign-in code."}
                    page = "Google did not return a sign-in code. Return to NOVA Copilot and try again."
                    status = 400
                body = ("<!doctype html><meta charset='utf-8'><title>NOVA Copilot</title>"
                        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
                        "<main style='font:16px -apple-system,BlinkMacSystemFont,sans-serif;max-width:34rem;margin:12vh auto;padding:2rem'>"
                        "<h2>NOVA Copilot</h2><p>" + page + "</p></main>").encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
                self.end_headers()
                self.wfile.write(body)

        try:
            verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode("ascii")
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode("ascii")).digest()).rstrip(b"=").decode("ascii")
            server = http.server.HTTPServer(("127.0.0.1", 8765), OAuthCallbackHandler)
            server.timeout = 120
            server.oauth_result = None
            try:
                query = urllib.parse.urlencode({
                    "provider": "google",
                    "redirect_to": GOOGLE_OAUTH_REDIRECT_URI,
                    "code_challenge": challenge,
                    "code_challenge_method": "s256",
                })
                authorization_url = f"{SUPABASE_URL}/auth/v1/authorize?{query}"
                if not webbrowser.open(authorization_url, new=1):
                    raise RuntimeError("Windows could not open your browser. Try again or use email sign-in.")
                server.handle_request()
                outcome = server.oauth_result
                if not outcome:
                    raise RuntimeError("Google sign-in timed out. Click Continue with Google and try again.")
                if outcome.get("error"):
                    raise RuntimeError(str(outcome["error"]))

                result = self._supabase_auth_request("/auth/v1/token?grant_type=pkce", {
 …8517 tokens truncated…) if messages[index].get("role") == "user"), None)
            if user_message is None:
                return
            thread["messages"].pop(latest_assistant_index)
            self.active_thread_id = thread["id"]
            self._render_conversation()
            self._update_mode_buttons()
            self._update_attachment_status()
            self._start_request(thread["id"], user_message["content"], existing_user_message=user_message)
            return

    def edit_and_save_docx(self, message_id: str) -> None:
        message = next((message for thread in self.threads for message in thread.get("messages", []) if message.get("id") == message_id), None)
        if message is None or not message.get("content"):
            return
        editor = tk.Toplevel(self.root)
        editor.title("Review Word document draft")
        editor.transient(self.root)
        editor.geometry("650x520")
        editor.minsize(440, 340)
        tk.Label(editor, text="Review and edit your draft", font=("Segoe UI Semibold", 12), anchor="w").pack(fill="x", padx=14, pady=(14, 4))
        tk.Label(editor, text="Saving exports plain text to a new .docx; the source document’s layout is not carried over.", fg=MUTED, anchor="w", wraplength=610, justify="left").pack(fill="x", padx=14, pady=(0, 8))
        body = tk.Frame(editor)
        body.pack(fill="both", expand=True, padx=14)
        draft = tk.Text(body, wrap="word", font=("Segoe UI", 10), padx=10, pady=9, undo=True)
        scroll = ttk.Scrollbar(body, orient="vertical", command=draft.yview)
        draft.configure(yscrollcommand=scroll.set)
        draft.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        draft.insert("1.0", message["content"])
        buttons = tk.Frame(editor)
        buttons.pack(fill="x", padx=14, pady=12)
        tk.Button(buttons, text="Close", command=editor.destroy).pack(side="right")

        def save_document() -> None:
            target = filedialog.asksaveasfilename(
                parent=editor,
                title="Save Word document",
                defaultextension=".docx",
                filetypes=[("Word document", "*.docx")],
            )
            if not target:
                return
            try:
                from docx import Document

                document = Document()
                for paragraph in draft.get("1.0", "end-1c").splitlines():
                    document.add_paragraph(paragraph)
                document.save(target)
                messagebox.showinfo("Word document saved", f"Saved to:\n{target}", parent=editor)
            except Exception as exc:
                messagebox.showerror("Word document", f"Could not save the .docx file.\n\n{exc}", parent=editor)

        tk.Button(buttons, text="Save .docx…", bg=ACCENT, fg=WHITE, relief="flat", padx=12, command=save_document).pack(side="right", padx=(0, 8))
        editor.grab_set()

    def _stream_reply(self, thread_id: str, message_id: str, messages: list[dict[str, str]], request_control: ActiveRequest) -> None:
        request = None
        response = None
        try:
            access_token = self._get_access_token()
            request = urllib.request.Request(
                CHAT_URL,
                data=json.dumps({"messages": messages}, ensure_ascii=False).encode("utf-8"),
                headers={
                    "Content-Type": "application/json",
                    "Accept": "text/plain, */*",
                    "User-Agent": f"NOVA-Copilot-Windows/{APP_VERSION}",
                    "Authorization": f"Bearer {access_token}",
                },
                method="POST",
            )
            response = urllib.request.urlopen(request, timeout=180)
            if not request_control.attach_response(response):
                self.events.put(("finished", (thread_id, message_id, None, True)))
                return
            decoder = __import__("codecs").getincrementaldecoder("utf-8")("replace")
            while not request_control.cancelled.is_set():
                chunk = response.read1(1024) if hasattr(response, "read1") else response.read(1024)
                if not chunk:
                    break
                text = decoder.decode(chunk)
                if text:
                    self.events.put(("delta", (thread_id, message_id, text)))
            tail = decoder.decode(b"", final=True)
            if tail:
                self.events.put(("delta", (thread_id, message_id, tail)))
            self.events.put(("finished", (thread_id, message_id, None, request_control.cancelled.is_set())))
        except urllib.error.HTTPError as exc:
            if request_control.cancelled.is_set():
                self.events.put(("finished", (thread_id, message_id, None, True)))
            else:
                try:
                    detail = exc.read(8192).decode("utf-8", "replace").strip()
                    try:
                        detail = json.loads(detail).get("error") or detail
                    except (json.JSONDecodeError, AttributeError):
                        pass
                except Exception:
                    detail = ""
                self.events.put(("finished", (thread_id, message_id, f"Nova V8 request failed (HTTP {exc.code}): {detail[:450]}", False)))
            try:
                exc.close()
            except Exception:
                pass
        except Exception as exc:
            if request_control.cancelled.is_set():
                self.events.put(("finished", (thread_id, message_id, None, True)))
            else:
                self.events.put(("finished", (thread_id, message_id, f"Connection error: {exc}", False)))
        finally:
            if response is not None:
                request_control.clear_response(response)
            try:
                if response:
                    response.close()
            except Exception:
                pass

    def stop_response(self) -> None:
        request_control = self.active_request
        if request_control is None:
            return
        self.active_request = None
        request_control.cancel()
        self.is_sending = False
        self.send_button.configure(text="↑", bg=ACCENT)
        self.status_label.configure(text="Response stopped")
        self.status_dot.configure(fg=GREEN if self.connected else ORANGE)

    def _find_message(self, thread_id: str, message_id: str) -> dict[str, Any] | None:
        for thread in self.threads:
            if thread["id"] == thread_id:
                for msg in thread["messages"]:
                    if msg["id"] == message_id:
                        return msg
        return None

    def _poll_events(self) -> None:
        if self._closing:
            return
        changed_messages: set[tuple[str, str]] = set()
        render_finished_thread = False
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "account-auth":
                    session, message, error = payload
                    self._account_auth_pending = False
                    if self._account_google_button and self._account_google_button.winfo_exists():
                        self._account_google_button.configure(text="Continue with Google", state="normal")
                    if session:
                        try:
                            self._save_auth_session(session)
                            self.auth_session = session
                            self._refresh_account_button()
                            if self._account_window:
                                self._close_account_window(self._account_window)
                            self.status_label.configure(text="Signed in to NOVA")
                            self.status_dot.configure(fg=GREEN)
                        except Exception as exc:
                            error = f"Could not securely save this session: {exc}"
                    elif self._account_status_label and self._account_status_label.winfo_exists():
                        self._account_status_label.configure(text=error or message, fg=ORANGE if error else ACCENT)
                        if self._account_submit_button and self._account_submit_button.winfo_exists():
                            self._account_submit_button.configure(text="Sign in", state="normal")
                elif kind == "auth-session":
                    self.auth_session = payload
                    self._refresh_account_button()
                    if self._account_identity_label and self._account_identity_label.winfo_exists():
                        identity = "This device’s guest profile" if payload.get("is_anonymous") else str(payload.get("email") or "NOVA account")
                        self._account_identity_label.configure(text=identity)
                        if not self._account_identity_label.winfo_manager() and self._owner_section and self._owner_section.winfo_exists():
                            self._account_identity_label.pack(fill="x", pady=(0, 5), before=self._owner_section)
                        if self._account_plan_label and self._account_plan_label.winfo_exists():
                            self._account_plan_label.configure(text="Unlimited owner messages" if self.is_owner else "25 messages per UTC day")
                elif kind == "owner-status":
                    self.is_owner = bool(payload)
                    self._owner_status_pending = False
                    if self._account_plan_label and self._account_plan_label.winfo_exists():
                        self._account_plan_label.configure(text="Unlimited owner messages" if self.is_owner else "25 messages per UTC day")
                    if self.is_owner:
                        if self._owner_section and self._owner_section.winfo_exists():
                            self._owner_section.pack_forget()
                        if self._account_signin_frame and self._account_signin_frame.winfo_exists():
                            self._account_signin_frame.pack_forget()
                        if self._account_signin_toggle_button and self._account_signin_toggle_button.winfo_exists():
                            self._account_signin_toggle_button.configure(text="Owner profile active", state="disabled")
                    elif self._account_signin_toggle_button and self._account_signin_toggle_button.winfo_exists():
                        self._account_signin_toggle_button.configure(state="normal")
                elif kind == "owner-redeem":
                    is_owner, error = payload
                    self._owner_redeem_pending = False
                    if self._owner_redeem_button and self._owner_redeem_button.winfo_exists():
                        self._owner_redeem_button.configure(text="Activate", state="normal")
                    if is_owner:
                        self.is_owner = True
                        self._owner_code_var.set("")
                        if self._account_status_label and self._account_status_label.winfo_exists():
                            self._account_status_label.configure(text="Owner profile activated. Your messages are unlimited.", fg=GREEN)
                        if self._account_plan_label and self._account_plan_label.winfo_exists():
                            self._account_plan_label.configure(text="Unlimited owner messages")
                        if self._owner_section and self._owner_section.winfo_exists():
                            self._owner_section.pack_forget()
                        if self._account_signin_frame and self._account_signin_frame.winfo_exists():
                            self._account_signin_frame.pack_forget()
                        if self._account_signin_toggle_button and self._account_signin_toggle_button.winfo_exists():
                            self._account_signin_toggle_button.configure(text="Owner profile active", state="disabled")
                    elif self._account_status_label and self._account_status_label.winfo_exists():
                        self._account_status_label.configure(text=error or "That owner code is invalid or already claimed.", fg=ORANGE)
                elif kind == "auth-expired":
                    self.auth_session = None
                    self.is_owner = False
                    self._refresh_account_button()
                    self.status_label.configure(text="Sign in again to continue")
                    self.status_dot.configure(fg=ORANGE)
                elif kind == "health":
                    self.connected, self.connection_status = payload
                    if not self.is_sending and not self._update_check_running:
                        self.status_label.configure(text=self.connection_status)
                        self.status_dot.configure(fg=GREEN if self.connected else ORANGE)
                elif kind == "delta":
                    thread_id, message_id, delta = payload
                    message = self._find_message(thread_id, message_id)
                    if message is not None:
                        message["content"] += delta
                        if self.active_request and self.active_request.message_id == message_id and message_id not in self._writing_message_ids:
                            self._writing_message_ids.add(message_id)
                            self.status_label.configure(text="Nova is writing…")
                        if thread_id == self.active_thread_id:
                            changed_messages.add((thread_id, message_id))
                        if time.monotonic() - self._last_save > 1.0:
                            self._save()
                            self._last_save = time.monotonic()
                elif kind == "finished":
                    thread_id, message_id, error, was_cancelled = payload
                    message = self._find_message(thread_id, message_id)
                    if message is not None:
                        if error:
                            message["content"] = (message["content"] + "\n\nConnection note: " if message["content"] else "Nova V8 error: ") + error
                        elif not message["content"]:
                            message["content"] = "Response stopped." if was_cancelled else "No response received."
                        if thread_id == self.active_thread_id:
                            changed_messages.add((thread_id, message_id))
                            render_finished_thread = True
                    getattr(self, "_writing_message_ids", set()).discard(message_id)
                    if self.active_request and self.active_request.message_id == message_id:
                        self.active_request = None
                        self.is_sending = False
                        self.send_button.configure(text="↑", bg=ACCENT)
                        if was_cancelled:
                            self.status_label.configure(text="Response stopped")
                        else:
                            self.status_label.configure(text="Request failed" if error else "Nova V8 connected")
                            self.status_dot.configure(fg=ORANGE if error else GREEN)
                    self._save()
                elif kind == "updates":
                    latest, error = payload
                    self._update_check_running = False
                    self.update_button.configure(text="Update", state="normal")
                    if error:
                        self.status_label.configure(text="Update check failed")
                        messagebox.showerror("Check for Updates", f"Could not check GitHub releases.\n\n{error}", parent=self.root)
                    elif latest is None:
                        self.status_label.configure(text=self.connection_status)
                        messagebox.showinfo("Check for Updates", "No Windows release is published yet.", parent=self.root)
                    else:
                        latest_tag = str(latest.get("tag_name", ""))
                        latest_version = latest_tag.removeprefix("windows-v")
                        if self._version_tuple(latest_tag) > self._version_tuple(APP_VERSION):
                            self.status_label.configure(text=f"NOVA Copilot {latest_version} is available")
                            if messagebox.askyesno(
                                "NOVA Copilot update available",
                                f"Version {latest_version} is available. Open its official GitHub release page?",
                                parent=self.root,
                            ):
                                webbrowser.open(latest.get("html_url", "https://github.com/Ethan-cat-a/NOVA/releases"))
                        else:
                            self.status_label.configure(text=f"NOVA Copilot {APP_VERSION} is up to date")
                            messagebox.showinfo("Check for Updates", f"NOVA Copilot for Windows {APP_VERSION} is up to date.", parent=self.root)
        except queue.Empty:
            pass
        if render_finished_thread:
            self._render_conversation()
        else:
            for thread_id, message_id in changed_messages:
                self._update_streamed_message(thread_id, message_id)
        self.root.after(100, self._poll_events)

    def _update_streamed_message(self, thread_id: str, message_id: str) -> None:
        if thread_id != self.active_thread_id:
            return
        message = self._find_message(thread_id, message_id)
        label = self.message_labels.get(message_id)
        if message is None or label is None:
            return

        try:
            was_at_bottom = self.canvas.yview()[1] >= 0.98
            label.configure(text=message.get("content") or "Thinking…")
            self.messages_frame.update_idletasks()
            self.canvas.configure(scrollregion=self.canvas.bbox("all"))
            if was_at_bottom:
                self.canvas.yview_moveto(1.0)
        except tk.TclError:
            pass

    def _poll_hotkey(self) -> None:
        if self._closing:
            return
        try:
            while True:
                self.hotkey_events.get_nowait()
                self.toggle_panel()
        except queue.Empty:
            pass
        self.root.after(100, self._poll_hotkey)

    def _report_hotkey_status(self) -> None:
        if self.hotkey.registered:
            self.hotkey_status = HOTKEY_LABEL
        else:
            self.hotkey_status = "Global shortcut unavailable (may already be in use)"
            self.shortcut_label.configure(text="Ctrl+Enter to send  ·  Global shortcut unavailable")

    def check_connection(self) -> None:
        self.status_label.configure(text="Checking Nova V8…")
        self.status_dot.configure(fg=ORANGE)
        threading.Thread(target=self._health_check_worker, daemon=True).start()

    def _health_check_worker(self) -> None:
        request = urllib.request.Request(CHAT_URL, headers={"User-Agent": f"NOVA-Copilot-Windows/{APP_VERSION}"}, method="GET")
        try:
            with urllib.request.urlopen(request, timeout=12) as response:
                data = json.loads(response.read(1024 * 64).decode("utf-8", "replace"))
            if data.get("ok") is True and data.get("keyConfigured") is True:
                self.events.put(("health", (True, "Nova V8 connected")))
            elif data.get("ok") is True:
                self.events.put(("health", (False, "Backend ready · API key unavailable")))
            else:
                self.events.put(("health", (False, "Nova V8 needs attention")))
        except Exception as exc:
            self.events.put(("health", (False, f"Connection unavailable: {exc}")))

    def _render_conversation(self) -> None:
        self.message_labels.clear()
        for child in self.messages_frame.winfo_children():
            child.destroy()
        messages = self.current_thread.get("messages", [])
        if not messages:
            self._render_welcome()
        else:
            for message in messages:
                self._render_message(message)
        self.messages_frame.update_idletasks()
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))
        self.canvas.yview_moveto(1.0)

    def _render_welcome(self) -> None:
        welcome = tk.Frame(self.messages_frame, bg=BG, padx=14, pady=16)
        welcome.pack(fill="x", anchor="n")
        tk.Label(welcome, text="Your AI, one shortcut away.", bg=BG, fg=INK, font=("Segoe UI", 20, "bold"), wraplength=350, justify="left").pack(anchor="w")
        tk.Label(welcome, text="Ask Nova V8, work through a problem, or bring in copied text from any Windows app.", bg=BG, fg=MUTED, font=("Segoe UI", 9), wraplength=350, justify="left").pack(anchor="w", pady=(7, 16))
        suggestions = [
            ("▤", "Summarize copied text", "Use context from another app", self.insert_clipboard),
            ("✎", "Help me write something", "Email, essay, or a clear reply", lambda: self._set_prompt("Help me write something. Ask any essential questions first, then draft it clearly.")),
            ("✦", "Explain this simply", "Make a difficult concept easier", lambda: self._set_prompt("Explain this concept simply, step by step, with a quick example: ")),
            ("</>", "Help with code", "Debug, build, or improve a project", self._prepare_coding_prompt),
        ]
        for icon, title, subtitle, action in suggestions:
            card = tk.Frame(welcome, bg=WHITE, highlightbackground=BORDER, highlightthickness=1, padx=10, pady=10, cursor="hand2")
            card.pack(fill="x", pady=4)
            card.bind("<Button-1>", lambda _e, fn=action: fn())
            tk.Label(card, text=icon, bg=ACCENT_LIGHT, fg=ACCENT, width=3, height=2, font=("Segoe UI", 12, "bold")).pack(side="left", padx=(0, 9))
            text_box = tk.Frame(card, bg=WHITE)
            text_box.pack(side="left", fill="x", expand=True)
            tk.Label(text_box, text=title, bg=WHITE, fg=INK, font=("Segoe UI", 9, "bold")).pack(anchor="w")
            tk.Label(text_box, text=subtitle, bg=WHITE, fg=MUTED, font=("Segoe UI", 8)).pack(anchor="w", pady=(2, 0))
            for child in text_box.winfo_children():
                child.bind("<Button-1>", lambda _e, fn=action: fn())
        tk.Label(welcome, text=f"Press {HOTKEY_LABEL} anywhere to open this panel", bg=BG, fg=MUTED, font=("Segoe UI", 8)).pack(anchor="w", pady=(12, 0))

    def _set_prompt(self, prompt: str) -> None:
        self.input_text.delete("1.0", "end")
        self.input_text.insert("1.0", prompt)
        self.input_text.focus_set()

    def _prepare_coding_prompt(self) -> None:
        self.set_mode("Coding")
        self._set_prompt("Help me debug or improve this code:\n")

    def _render_message(self, message: dict[str, Any]) -> None:
        is_user = message.get("role") == "user"
        row = tk.Frame(self.messages_frame, bg=BG, padx=10, pady=6)
        row.pack(fill="x", anchor="e" if is_user else "w")
        if is_user:
            wrapper = tk.Frame(row, bg=USER_BUBBLE, padx=11, pady=9)
            wrapper.pack(side="right", anchor="e")
            label = tk.Label(wrapper, text=message.get("content", ""), bg=USER_BUBBLE, fg=WHITE, justify="left", anchor="w", wraplength=285, font=("Segoe UI", 9))
            label.pack(anchor="w")
            label.bind("<Button-3>", lambda e, txt=message.get("content", ""): self._copy_text(txt))
            wrapper.bind("<Button-3>", lambda e, txt=message.get("content", ""): self._copy_text(txt))
        else:
            wrapper = tk.Frame(row, bg=WHITE, highlightbackground=BORDER, highlightthickness=1, padx=11, pady=9)
            wrapper.pack(side="left", fill="x", expand=True, padx=(0, 22))
            tk.Label(wrapper, text="NOVA V8", bg=WHITE, fg=MUTED, font=("Segoe UI", 7, "bold")).pack(anchor="w", pady=(0, 4))
            content = message.get("content", "")
            if not content:
                content = "Thinking…"
            label = tk.Label(wrapper, text=content, bg=WHITE, fg=INK, justify="left", anchor="w", wraplength=315, font=("Segoe UI", 9))
            label.pack(anchor="w", fill="x")
            message_id = message.get("id")
            if message_id:
                self.message_labels[message_id] = label
                label.bind("<Button-3>", lambda _e, mid=message_id: self._copy_message(mid))
                wrapper.bind("<Button-3>", lambda _e, mid=message_id: self._copy_message(mid))
                complete = not (self.active_request and self.active_request.message_id == message_id)
                if complete and message.get("content"):
                    actions = tk.Frame(wrapper, bg=WHITE)
                    actions.pack(anchor="w", pady=(7, 0))
                    tk.Button(actions, text="Copy", relief="flat", bd=0, bg=WHITE, fg=ACCENT, font=("Segoe UI", 8), cursor="hand2", command=lambda mid=message_id: self._copy_message(mid)).pack(side="left", padx=(0, 10))
                    if self._is_latest_assistant(message_id):
                        tk.Button(actions, text="Try again", relief="flat", bd=0, bg=WHITE, fg=ACCENT, font=("Segoe UI", 8), cursor="hand2", command=lambda mid=message_id: self.retry_response(mid)).pack(side="left", padx=(0, 10))
                    if message.get("word_doc_mode"):
                        tk.Button(actions, text="Edit / Save .docx", relief="flat", bd=0, bg=WHITE, fg=ACCENT, font=("Segoe UI", 8), cursor="hand2", command=lambda mid=message_id: self.edit_and_save_docx(mid)).pack(side="left")
            else:
                label.bind("<Button-3>", lambda _e, txt=message.get("content", ""): self._copy_text(txt))
                wrapper.bind("<Button-3>", lambda _e, txt=message.get("content", ""): self._copy_text(txt))

    def _is_latest_assistant(self, message_id: str) -> bool:
        messages = self.current_thread.get("messages", [])
        latest = next((message for message in reversed(messages) if message.get("role") == "assistant"), None)
        return bool(latest and latest.get("id") == message_id)

    def _copy_message(self, message_id: str) -> None:
        for thread in self.threads:
            for message in thread.get("messages", []):
                if message.get("id") == message_id:
                    self._copy_text(message.get("content", ""))
                    return

    def _copy_text(self, text: str) -> None:
        if not text:
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        self.status_label.configure(text="Copied to clipboard")
        self.root.after(1800, lambda: self.status_label.configure(text=self.connection_status) if not self.is_sending and not self._update_check_running else None)

    def _on_messages_configure(self, _event: tk.Event) -> None:
        self.canvas.configure(scrollregion=self.canvas.bbox("all"))

    def _on_canvas_configure(self, event: tk.Event) -> None:
        self.canvas.itemconfigure(self.messages_window, width=event.width)

    def _on_mousewheel(self, event: tk.Event) -> None:
        if self.root.state() != "withdrawn":
            self.canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")

    def _save(self) -> None:
        self.threads.sort(key=lambda x: x.get("updated_at", ""), reverse=True)
        if len(self.threads) > 40:
            self.threads = self.threads[:40]
        save_threads(self.threads)

    def _is_launch_at_login(self) -> bool:
        if os.name != "nt":
            return False
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run") as key:
                winreg.QueryValueEx(key, "NOVACopilot")
            return True
        except Exception:
            return False

    def _menu_toggle_launch_at_login(self) -> None:
        # The BooleanVar is toggled by Tk before this callback runs.
        requested = bool(self.login_menu_var.get())
        currently_enabled = self.launch_at_login
        if requested != currently_enabled:
            self.toggle_launch_at_login()
        self.login_menu_var.set(self.launch_at_login)

    def toggle_launch_at_login(self) -> None:
        try:
            import winreg
            key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0, winreg.KEY_SET_VALUE) as key:
                if self.launch_at_login:
                    winreg.DeleteValue(key, "NOVACopilot")
                    self.launch_at_login = False
                else:
                    if getattr(sys, "frozen", False):
                        command = f'"{sys.executable}"'
                    else:
                        script = str(Path(__file__).resolve())
                        pythonw = Path(sys.executable).with_name("pythonw.exe")
                        runner = str(pythonw if pythonw.exists() else Path(sys.executable))
                        command = f'"{runner}" "{script}"'
                    winreg.SetValueEx(key, "NOVACopilot", 0, winreg.REG_SZ, command)
                    self.launch_at_login = True
            if hasattr(self, "login_menu_var"):
                self.login_menu_var.set(self.launch_at_login)
        except Exception as exc:
            messagebox.showerror("Launch at Login", f"Could not update the Windows startup setting.\n\n{exc}", parent=self.root)

    def _create_tray_image(self):
        if Image is None:
            return None
        image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.ellipse((3, 3, 61, 61), fill="#14284E")
        try:
            font = ImageFont.truetype("segoeuib.ttf", 39)
        except Exception:
            font = ImageFont.load_default()
        box = draw.textbbox((0, 0), "N", font=font)
        draw.text(((64 - (box[2] - box[0])) / 2, (64 - (box[3] - box[1])) / 2 - box[1] - 1), "N", fill="white", font=font)
        return image

    def _start_tray(self) -> None:
        if pystray is None:
            return
        try:
            menu = pystray.Menu(
                pystray.MenuItem("Show NOVA Copilot", lambda: self.root.after(0, self.show_panel), default=True),
                pystray.MenuItem("New chat", lambda: self.root.after(0, self.new_chat)),
                pystray.MenuItem("Check Nova connection", lambda: self.root.after(0, self.check_connection)),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Quit NOVA Copilot", lambda: self.root.after(0, self.quit_app)),
            )
            self.tray_icon = pystray.Icon("nova_copilot", self._create_tray_image(), APP_NAME, menu)
            self.tray_thread = threading.Thread(target=self.tray_icon.run, name="NOVA-Tray", daemon=True)
            self.tray_thread.start()
        except Exception:
            self.tray_icon = None

    def quit_app(self) -> None:
        if self._closing:
            return
        self._closing = True
        request_control = self.active_request
        self.active_request = None
        if request_control is not None:
            request_control.cancel()
        self.hotkey.stop()
        try:
            if self.tray_icon:
                self.tray_icon.stop()
        except Exception:
            pass
        try:
            self.root.destroy()
        except tk.TclError:
            pass

    def run(self) -> None:
        self.root.mainloop()


def main() -> None:
    try:
        app = NovaCopilotApp()
        app.run()
    except Exception as exc:
        try:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror(APP_NAME, f"NOVA Copilot could not start.\n\n{exc}")
            root.destroy()
        except Exception:
            print(f"{APP_NAME} startup error: {exc}", file=sys.stderr)


if __name__ == "__main__":
    main()

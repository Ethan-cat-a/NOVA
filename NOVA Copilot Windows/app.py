from __future__ import annotations

import ctypes
import ctypes.wintypes
import json
import os
import queue
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import tkinter as tk
from tkinter import messagebox, ttk

try:
    import pystray
    from PIL import Image, ImageDraw, ImageFont
except Exception:  # Tray support is optional when running directly from source.
    pystray = None
    Image = ImageDraw = ImageFont = None

APP_NAME = "NOVA Copilot"
APP_VERSION = "1.0.0"
CHAT_URL = "https://nova-v8.vercel.app/api/chat"
HOTKEY_LABEL = "Ctrl + Shift + Space"

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
        self.active_thread_id = self.threads[0]["id"]
        self.is_sending = False
        self.request_cancel = threading.Event()
        self.active_response = None
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

    def _configure_styles(self) -> None:
        style = ttk.Style(self.root)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TFrame", background=BG)
        style.configure("White.TFrame", background=WHITE)
        style.configure("TLabel", background=BG, foreground=INK, font=("Segoe UI", 10))
        style.configure("Muted.TLabel", background=BG, foreground=MUTED, font=("Segoe UI", 9))
        style.configure("Header.TLabel", background=WHITE, foreground=INK, font=("Segoe UI Semibold", 12))
        style.configure("Small.TButton", padding=(8, 5), font=("Segoe UI", 9))
        style.configure("Mode.TButton", padding=(8, 6), font=("Segoe UI", 9))
        style.configure("Accent.TButton", padding=(12, 8), background=ACCENT, foreground=WHITE, font=("Segoe UI Semibold", 9))
        style.map("Accent.TButton", background=[("active", "#1F47A5"), ("disabled", "#AAB9DD")])
        style.configure("TEntry", padding=8)

    def _build_ui(self) -> None:
        header = tk.Frame(self.root, bg=WHITE, padx=15, pady=12)
        header.pack(fill="x")

        logo = tk.Canvas(header, width=36, height=36, bg=WHITE, highlightthickness=0)
        logo.pack(side="left", padx=(0, 10))
        logo.create_oval(1, 1, 35, 35, fill="#14284E", outline="#14284E")
        logo.create_text(18, 18, text="N", fill=WHITE, font=("Segoe UI", 17, "bold"))

        title_area = tk.Frame(header, bg=WHITE)
        title_area.pack(side="left", fill="x", expand=True)
        title_line = tk.Frame(title_area, bg=WHITE)
        title_line.pack(anchor="w")
        tk.Label(title_line, text="NOVA COPILOT", bg=WHITE, fg=INK, font=("Segoe UI", 11, "bold")).pack(side="left")
        tk.Label(title_line, text="  V8 CORE", bg=ACCENT_LIGHT, fg=ACCENT, font=("Segoe UI", 7, "bold"), padx=5, pady=3).pack(side="left", padx=(7, 0))
        status_line = tk.Frame(title_area, bg=WHITE)
        status_line.pack(anchor="w", pady=(4, 0))
        self.status_dot = tk.Label(status_line, text="●", bg=WHITE, fg=ORANGE, font=("Segoe UI", 8))
        self.status_dot.pack(side="left")
        self.status_label = tk.Label(status_line, text=self.connection_status, bg=WHITE, fg=MUTED, font=("Segoe UI", 8))
        self.status_label.pack(side="left", padx=(4, 0))

        self.pin_button = tk.Button(header, text="📌", relief="flat", bd=0, bg=WHITE, fg=ACCENT, activebackground=ACCENT_LIGHT, command=self.toggle_pin, cursor="hand2")
        self.pin_button.pack(side="right", padx=(4, 0))
        self.more_button = tk.Menubutton(header, text="⋯", relief="flat", bd=0, bg=WHITE, fg=MUTED, activebackground=BG, font=("Segoe UI", 17), cursor="hand2")
        self.more_button.pack(side="right")
        self._build_more_menu()
        self.more_button.configure(menu=self.more_menu)
        self.history_button = tk.Menubutton(header, text="▾", relief="flat", bd=0, bg=WHITE, fg=MUTED, activebackground=BG, cursor="hand2")
        self.history_button.pack(side="right", padx=(0, 3))
        self._build_history_menu()

        tk.Frame(self.root, bg=BORDER, height=1).pack(fill="x")

        mode_frame = tk.Frame(self.root, bg=WHITE, padx=15, pady=9)
        mode_frame.pack(fill="x")
        tk.Label(mode_frame, text="MODE", bg=WHITE, fg=MUTED, font=("Segoe UI", 8, "bold")).pack(side="left", padx=(0, 10))
        self.mode_buttons: dict[str, tk.Button] = {}
        for mode in MODE_INSTRUCTIONS:
            button = tk.Button(mode_frame, text=mode, relief="flat", bd=0, padx=9, pady=5, font=("Segoe UI", 8), cursor="hand2", command=lambda m=mode: self.set_mode(m))
            button.pack(side="left", padx=(0, 5))
            self.mode_buttons[mode] = button
        self._update_mode_buttons()

        tk.Frame(self.root, bg=BORDER, height=1).pack(fill="x")

        self.conversation_host = tk.Frame(self.root, bg=BG)
        self.conversation_host.pack(fill="both", expand=True)
        self.canvas = tk.Canvas(self.conversation_host, bg=BG, highlightthickness=0)
        self.scrollbar = ttk.Scrollbar(self.conversation_host, orient="vertical", command=self.canvas.yview)
        self.messages_frame = tk.Frame(self.canvas, bg=BG)
        self.messages_window = self.canvas.create_window((0, 0), window=self.messages_frame, anchor="nw")
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.scrollbar.pack(side="right", fill="y")
        self.messages_frame.bind("<Configure>", self._on_messages_configure)
        self.canvas.bind("<Configure>", self._on_canvas_configure)
        self.canvas.bind_all("<MouseWheel>", self._on_mousewheel)

        composer = tk.Frame(self.root, bg=WHITE, padx=12, pady=10)
        composer.pack(fill="x", side="bottom")
        tk.Frame(composer, bg=BORDER, height=1).pack(fill="x", pady=(0, 9))
        controls = tk.Frame(composer, bg=WHITE)
        controls.pack(fill="x")
        self.attach_button = tk.Button(controls, text="＋", font=("Segoe UI", 15), width=3, relief="flat", bd=0, bg=BG, fg=MUTED, activebackground=ACCENT_LIGHT, command=self.insert_clipboard, cursor="hand2")
        self.attach_button.pack(side="left", padx=(0, 7))
        self.input_text = tk.Text(controls, height=2, wrap="word", font=("Segoe UI", 10), relief="flat", bd=0, bg="#F8FAFD", fg=INK, insertbackground=INK, padx=10, pady=9, undo=True)
        self.input_text.pack(side="left", fill="x", expand=True)
        self.input_text.bind("<Control-Return>", self._send_shortcut)
        self.input_text.bind("<Shift-Return>", lambda _e: None)
        self.send_button = tk.Button(controls, text="↑", font=("Segoe UI", 15, "bold"), width=3, relief="flat", bd=0, bg=ACCENT, fg=WHITE, activebackground="#1F47A5", command=self.send_or_stop, cursor="hand2")
        self.send_button.pack(side="left", padx=(7, 0))
        footer = tk.Frame(composer, bg=WHITE)
        footer.pack(fill="x", pady=(7, 0))
        self.shortcut_label = tk.Label(footer, text="Ctrl+Enter to send  ·  Ctrl+Shift+Space to toggle", bg=WHITE, fg=MUTED, font=("Segoe UI", 7))
        self.shortcut_label.pack(side="left")
        tk.Label(footer, text="Chats saved on this PC", bg=WHITE, fg=MUTED, font=("Segoe UI", 7)).pack(side="right")

        self._render_conversation()
        self.root.after(250, self.input_text.focus_set)

    def _build_more_menu(self) -> None:
        self.more_menu = tk.Menu(self.root, tearoff=0, font=("Segoe UI", 9))
        self.more_menu.add_command(label="New chat", command=self.new_chat)
        self.more_menu.add_separator()
        self.pin_menu_var = tk.BooleanVar(value=self.pinned)
        self.login_menu_var = tk.BooleanVar(value=self.launch_at_login)
        self.more_menu.add_checkbutton(label="Keep on top", variable=self.pin_menu_var, command=self._menu_toggle_pin)
        self.more_menu.add_checkbutton(label="Launch at Login", variable=self.login_menu_var, command=self._menu_toggle_launch_at_login)
        self.more_menu.add_command(label="Check Nova connection", command=self.check_connection)
        self.more_menu.add_command(label="Clear current chat", command=self.clear_current_chat)
        self.more_menu.add_separator()
        self.more_menu.add_command(label="Hide panel", command=self.hide_panel)
        self.more_menu.add_command(label="Quit NOVA Copilot", command=self.quit_app)

    def _build_history_menu(self) -> None:
        self.history_menu = tk.Menu(self.root, tearoff=0, font=("Segoe UI", 9))
        self.history_button.configure(menu=self.history_menu)
        self._refresh_history_menu()

    def _refresh_history_menu(self) -> None:
        if not hasattr(self, "history_menu"):
            return
        self.history_menu.delete(0, "end")
        for thread in self.threads[:12]:
            title = thread.get("title") or "New chat"
            label = title[:48]
            if thread["id"] == self.active_thread_id:
                label = "✓  " + label
            self.history_menu.add_command(label=label, command=lambda tid=thread["id"]: self.switch_thread(tid))
        self.history_menu.add_separator()
        self.history_menu.add_command(label="New chat…", command=self.new_chat)

    def _create_edge_handle(self) -> None:
        self.edge_window = tk.Toplevel(self.root)
        self.edge_window.overrideredirect(True)
        self.edge_window.attributes("-topmost", True)
        self.edge_window.configure(bg="#14284E")
        self.edge_window.geometry("42x112+0+0")
        self.edge_window.withdraw()
        handle = tk.Button(self.edge_window, text="✦\n│\nNOVA\n›", font=("Segoe UI", 9, "bold"), bg="#14284E", fg=WHITE, activebackground="#213D70", activeforeground=WHITE, relief="flat", bd=0, cursor="hand2", command=self.show_panel)
        handle.pack(fill="both", expand=True)
        self.edge_window.bind("<Enter>", lambda _e: self.edge_window.attributes("-alpha", 1.0))

    def show_edge_handle(self) -> None:
        if self._closing or not self.edge_window:
            return
        try:
            self.root.update_idletasks()
            screen_h = self.root.winfo_screenheight()
            screen_w = self.root.winfo_screenwidth()
            y = max(80, (screen_h - 112) // 2)
            self.edge_window.geometry(f"42x112+{screen_w - 42}+{y}")
            self.edge_window.deiconify()
            self.edge_window.lift()
        except tk.TclError:
            pass

    def show_panel(self) -> None:
        if self._closing:
            return
        if self.edge_window:
            self.edge_window.withdraw()
        self.root.deiconify()
        self.root.lift()
        if self.pinned:
            self.root.attributes("-topmost", True)
        self.root.focus_force()
        self.input_text.focus_set()

    def hide_panel(self) -> None:
        if self._closing:
            return
        self.root.withdraw()
        self.show_edge_handle()

    def toggle_panel(self) -> None:
        if self.root.state() == "withdrawn":
            self.show_panel()
        else:
            self.hide_panel()

    def _menu_toggle_pin(self) -> None:
        self.pinned = bool(self.pin_menu_var.get())
        self._apply_pin_state()

    def toggle_pin(self) -> None:
        self.pinned = not self.pinned
        if hasattr(self, "pin_menu_var"):
            self.pin_menu_var.set(self.pinned)
        self._apply_pin_state()

    def _apply_pin_state(self) -> None:
        self.root.attributes("-topmost", self.pinned)
        self.pin_button.configure(fg=ACCENT if self.pinned else MUTED, text="📌" if self.pinned else "⌖")

    def set_mode(self, mode: str) -> None:
        self.current_thread["mode"] = mode
        self.current_thread["updated_at"] = utc_now()
        self._update_mode_buttons()
        self._save()

    def _update_mode_buttons(self) -> None:
        selected = self.current_thread.get("mode", "Fast")
        for mode, button in getattr(self, "mode_buttons", {}).items():
            active = mode == selected
            button.configure(bg=ACCENT_LIGHT if active else WHITE, fg=ACCENT if active else MUTED, font=("Segoe UI", 8, "bold" if active else "normal"))

    def new_chat(self) -> None:
        if self.is_sending:
            self.stop_response()
        thread = new_thread()
        self.threads.insert(0, thread)
        self.active_thread_id = thread["id"]
        self.input_text.delete("1.0", "end")
        self._save()
        self._render_conversation()
        self._refresh_history_menu()
        self.input_text.focus_set()

    def switch_thread(self, thread_id: str) -> None:
        if not any(t["id"] == thread_id for t in self.threads):
            return
        if self.is_sending:
            self.stop_response()
        self.active_thread_id = thread_id
        self.input_text.delete("1.0", "end")
        self._render_conversation()
        self._update_mode_buttons()
        self._refresh_history_menu()
        self.input_text.focus_set()

    def clear_current_chat(self) -> None:
        if self.is_sending:
            self.stop_response()
        self.current_thread["messages"] = []
        self.current_thread["title"] = "New chat"
        self.current_thread["updated_at"] = utc_now()
        self._save()
        self._render_conversation()
        self._refresh_history_menu()

    def insert_clipboard(self) -> None:
        try:
            copied = self.root.clipboard_get().strip()
        except tk.TclError:
            copied = ""
        if not copied:
            messagebox.showinfo("Clipboard", "No text found. Copy some text in any app first.", parent=self.root)
            return
        context = "Use this copied text as context.\\n\\n--- Clipboard text ---\\n" + copied[:18000] + "\\n--- End clipboard text ---\\n"
        existing = self.input_text.get("1.0", "end-1c").strip()
        self.input_text.delete("1.0", "end")
        self.input_text.insert("1.0", (existing + "\\n\\n" if existing else "") + context)
        self.input_text.focus_set()

    def _send_shortcut(self, _event: tk.Event) -> str:
        self.send_or_stop()
        return "break"

    def send_or_stop(self) -> None:
        if self.is_sending:
            self.stop_response()
            return
        prompt = self.input_text.get("1.0", "end-1c").strip()
        if not prompt:
            return
        thread = self.current_thread
        thread_id = thread["id"]
        if not thread["messages"] or thread.get("title") == "New chat":
            thread["title"] = prompt.replace("\\n", " ")[:42]
        thread["messages"].append({"id": str(uuid.uuid4()), "role": "user", "content": prompt, "created_at": utc_now()})
        self.response_message_id = str(uuid.uuid4())
        thread["messages"].append({"id": self.response_message_id, "role": "assistant", "content": "", "created_at": utc_now()})
        thread["updated_at"] = utc_now()
        self.input_text.delete("1.0", "end")
        self.is_sending = True
        self.request_cancel = threading.Event()
        self.send_button.configure(text="■", bg="#596579")
        self.status_label.configure(text="Nova is thinking…")
        self.status_dot.configure(fg=ORANGE)
        self._save()
        self._render_conversation()
        self._refresh_history_menu()

        mode = thread.get("mode", "Fast")
        api_mode = {"Fast": "fast", "Hard Thinker": "thinker", "Coding": "coding"}[mode]
        api_messages = [{
            "role": "assistant",
            "content": (
                f"Active response mode ({api_mode}): {MODE_INSTRUCTIONS[mode]} "
                "Canonical Nova lore: Nova was created at Nova AI headquarters by Ethan. If asked where Nova was created, state that Nova was created at Nova AI headquarters. "
                "For normal answers, be concise and start with the direct answer. Avoid filler and unnecessary preambles. Do not use asterisks."
            ),
        }]
        api_messages.extend({"role": m["role"], "content": m["content"]} for m in thread["messages"][:-1][-10:])
        threading.Thread(target=self._stream_reply, args=(thread_id, self.response_message_id, api_messages, self.request_cancel), daemon=True).start()

    def _stream_reply(self, thread_id: str, message_id: str, messages: list[dict[str, str]], cancel: threading.Event) -> None:
        request = urllib.request.Request(
            CHAT_URL,
            data=json.dumps({"messages": messages}, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json", "Accept": "text/plain, */*", "User-Agent": f"NOVA-Copilot-Windows/{APP_VERSION}"},
            method="POST",
        )
        response = None
        try:
            response = urllib.request.urlopen(request, timeout=180)
            self.active_response = response
            decoder = __import__("codecs").getincrementaldecoder("utf-8")("replace")
            while not cancel.is_set():
                chunk = response.read1(1024) if hasattr(response, "read1") else response.read(1024)
                if not chunk:
                    break
                text = decoder.decode(chunk)
                if text:
                    self.events.put(("delta", (thread_id, message_id, text)))
            tail = decoder.decode(b"", final=True)
            if tail:
                self.events.put(("delta", (thread_id, message_id, tail)))
            self.events.put(("finished", (thread_id, message_id, None, cancel.is_set())))
        except urllib.error.HTTPError as exc:
            try:
                detail = exc.read(8192).decode("utf-8", "replace").strip()
            except Exception:
                detail = ""
            self.events.put(("finished", (thread_id, message_id, f"Nova V8 request failed (HTTP {exc.code}): {detail[:450]}", False)))
        except Exception as exc:
            if cancel.is_set():
                self.events.put(("finished", (thread_id, message_id, None, True)))
            else:
                self.events.put(("finished", (thread_id, message_id, f"Connection error: {exc}", False)))
        finally:
            try:
                if response:
                    response.close()
            except Exception:
                pass
            self.active_response = None

    def stop_response(self) -> None:
        self.request_cancel.set()
        try:
            if self.active_response:
                self.active_response.close()
        except Exception:
            pass
        self.send_button.configure(text="…", bg="#596579")
        self.status_label.configure(text="Stopping response…")

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
        changed = False
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "health":
                    self.connected, self.connection_status = payload
                    self.status_label.configure(text=self.connection_status)
                    self.status_dot.configure(fg=GREEN if self.connected else ORANGE)
                elif kind == "delta":
                    thread_id, message_id, delta = payload
                    message = self._find_message(thread_id, message_id)
                    if message is not None:
                        message["content"] += delta
                        if thread_id == self.active_thread_id:
                            changed = True
                        if time.monotonic() - self._last_save > 1.0:
                            self._save()
                            self._last_save = time.monotonic()
                elif kind == "finished":
                    thread_id, message_id, error, was_cancelled = payload
                    message = self._find_message(thread_id, message_id)
                    if message is not None:
                        if error:
                            message["content"] = (message["content"] + "\\n\\nConnection note: " if message["content"] else "Nova V8 error: ") + error
                        elif not message["content"]:
                            message["content"] = "Response stopped." if was_cancelled else "No response received."
                    self.is_sending = False
                    self.send_button.configure(text="↑", bg=ACCENT)
                    self.status_label.configure(text="Nova V8 connected" if not error else "Request failed")
                    self.status_dot.configure(fg=GREEN if not error else ORANGE)
                    self._save()
                    changed = True
        except queue.Empty:
            pass
        if changed:
            self._render_conversation()
        self.root.after(100, self._poll_events)

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
            card = tk.Frame(self.messages_frame, bg=WHITE, highlightbackground=BORDER, highlightthickness=1, padx=10, pady=10, cursor="hand2")
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
            label.bind("<Button-3>", lambda e, txt=message.get("content", ""): self._copy_text(txt))
            wrapper.bind("<Button-3>", lambda e, txt=message.get("content", ""): self._copy_text(txt))

    def _copy_text(self, text: str) -> None:
        if not text:
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(text)

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
        self.request_cancel.set()
        self.hotkey.stop()
        try:
            if self.active_response:
                self.active_response.close()
        except Exception:
            pass
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

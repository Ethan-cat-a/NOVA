import importlib.util
import os
import queue
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
WINDOWS_APP = ROOT / "NOVA Copilot Windows" / "app.py"
TEST_DATA = tempfile.TemporaryDirectory(prefix="nova-windows-tests-")
os.environ["LOCALAPPDATA"] = TEST_DATA.name

spec = importlib.util.spec_from_file_location("nova_windows_app", WINDOWS_APP)
nova = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = nova
spec.loader.exec_module(nova)


class FakeResponse:
    def __init__(self, chunks=()):
        self.chunks = iter(chunks)
        self.closed = False

    def read1(self, _size):
        return next(self.chunks, b"")

    def close(self):
        self.closed = True


class FakeLabel:
    def __init__(self):
        self.text = ""

    def configure(self, **kwargs):
        self.text = kwargs.get("text", self.text)


class FakeWidget:
    def __init__(self):
        self.options = {}

    def configure(self, **kwargs):
        self.options.update(kwargs)


class FakeCanvas:
    def __init__(self, yview=(0.0, 0.7)):
        self.view = yview
        self.scrollregion = None
        self.scroll_to_bottom = False

    def yview(self):
        return self.view

    def bbox(self, _item):
        return (0, 0, 100, 100)

    def configure(self, **kwargs):
        self.scrollregion = kwargs.get("scrollregion")

    def yview_moveto(self, value):
        self.scroll_to_bottom = value == 1.0


class WindowsAppTests(unittest.TestCase):
    def test_active_request_cancel_closes_attached_response(self):
        request = nova.ActiveRequest("response-id")
        response = FakeResponse()
        self.assertTrue(request.attach_response(response))

        request.cancel()

        self.assertTrue(request.cancelled.is_set())
        self.assertTrue(response.closed)

    def test_response_opening_after_cancel_is_closed_immediately(self):
        request = nova.ActiveRequest("response-id")
        request.cancel()
        response = FakeResponse()

        self.assertFalse(request.attach_response(response))
        self.assertTrue(response.closed)

    def test_stop_releases_ui_and_closes_an_open_response(self):
        request = nova.ActiveRequest("response-id")
        response = FakeResponse()
        request.attach_response(response)
        send_button = FakeWidget()
        status_label = FakeWidget()
        status_dot = FakeWidget()
        app = SimpleNamespace(
            active_request=request,
            is_sending=True,
            send_button=send_button,
            status_label=status_label,
            status_dot=status_dot,
            connection_status="Nova V8 connected",
            connected=False,
        )

        nova.NovaCopilotApp.stop_response(app)

        self.assertIsNone(app.active_request)
        self.assertFalse(app.is_sending)
        self.assertTrue(request.cancelled.is_set())
        self.assertTrue(response.closed)
        self.assertEqual(send_button.options["text"], "↑")
        self.assertEqual(status_label.options["text"], "Response stopped")

    def test_stream_decodes_utf8_split_across_network_chunks(self):
        response = FakeResponse([b"Hello ", b"\xe4", b"\xbd", b"\xa0!"])
        control = nova.ActiveRequest("response-id")
        app = SimpleNamespace(events=queue.Queue())
        with patch.object(nova.urllib.request, "urlopen", return_value=response):
            nova.NovaCopilotApp._stream_reply(
                app,
                "thread-id",
                "response-id",
                [{"role": "user", "content": "hi"}],
                control,
            )

        events = []
        while not app.events.empty():
            events.append(app.events.get_nowait())
        text = "".join(payload[2] for kind, payload in events if kind == "delta")
        self.assertEqual(text, "Hello 你!")
        self.assertEqual(events[-1][0], "finished")
        self.assertTrue(response.closed)

    def test_stream_delta_updates_label_without_moving_scrolled_view(self):
        label = FakeLabel()
        canvas = FakeCanvas(yview=(0.2, 0.8))
        message = {"id": "response-id", "content": "A partial answer"}
        app = SimpleNamespace(
            active_thread_id="thread-id",
            message_labels={"response-id": label},
            canvas=canvas,
            messages_frame=SimpleNamespace(update_idletasks=lambda: None),
            _find_message=lambda _thread_id, _message_id: message,
        )

        nova.NovaCopilotApp._update_streamed_message(app, "thread-id", "response-id")

        self.assertEqual(label.text, "A partial answer")
        self.assertEqual(canvas.scrollregion, (0, 0, 100, 100))
        self.assertFalse(canvas.scroll_to_bottom)

    def test_stream_delta_keeps_view_at_bottom_when_already_there(self):
        label = FakeLabel()
        canvas = FakeCanvas(yview=(0.5, 1.0))
        message = {"id": "response-id", "content": "A partial answer"}
        app = SimpleNamespace(
            active_thread_id="thread-id",
            message_labels={"response-id": label},
            canvas=canvas,
            messages_frame=SimpleNamespace(update_idletasks=lambda: None),
            _find_message=lambda _thread_id, _message_id: message,
        )

        nova.NovaCopilotApp._update_streamed_message(app, "thread-id", "response-id")

        self.assertTrue(canvas.scroll_to_bottom)

    def test_stream_events_update_in_place_without_full_rerender(self):
        events = queue.Queue()
        events.put(("delta", ("thread-id", "response-id", "new text")))
        updates = []
        message = {"id": "response-id", "content": ""}
        root_calls = []
        app = SimpleNamespace(
            _closing=False,
            events=events,
            active_thread_id="thread-id",
            active_request=None,
            is_sending=False,
            send_button=None,
            status_label=None,
            status_dot=None,
            _last_save=time.monotonic(),
            _find_message=lambda _thread_id, _message_id: message,
            _save=lambda: None,
            _update_streamed_message=lambda thread_id, message_id: updates.append((thread_id, message_id)),
            _poll_events=lambda: None,
            root=SimpleNamespace(after=lambda *args: root_calls.append(args)),
        )

        nova.NovaCopilotApp._poll_events(app)

        self.assertEqual(message["content"], "new text")
        self.assertEqual(updates, [("thread-id", "response-id")])
        self.assertEqual(len(root_calls), 1)

    def test_old_cancelled_request_cannot_reset_new_request_state(self):
        events = queue.Queue()
        events.put(("finished", ("thread-id", "old-response", None, True)))
        new_request = nova.ActiveRequest("new-response")
        status_label = FakeWidget()
        send_button = FakeWidget()
        app = SimpleNamespace(
            _closing=False,
            events=events,
            active_thread_id="thread-id",
            active_request=new_request,
            is_sending=True,
            send_button=send_button,
            status_label=status_label,
            status_dot=FakeWidget(),
            _last_save=time.monotonic(),
            _find_message=lambda _thread_id, _message_id: None,
            _save=lambda: None,
            _update_streamed_message=lambda *_args: None,
            _poll_events=lambda: None,
            root=SimpleNamespace(after=lambda *_args: None),
        )

        nova.NovaCopilotApp._poll_events(app)

        self.assertIs(app.active_request, new_request)
        self.assertTrue(app.is_sending)
        self.assertEqual(status_label.options, {})


if __name__ == "__main__":
    unittest.main()

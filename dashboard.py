#!/usr/bin/env python3
"""
Event, Conference and Venue Management System - Native macOS Web Dashboard
Team: Shreya Adhikari (TCA2573041)

Zero external Python dependencies required!
Run directly on macOS:
    python3 dashboard.py
Then open: http://localhost:8502
"""

import json
import os
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

import db_engine

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_PATH = os.path.join(BASE_DIR, "templates", "index.html")
DEFAULT_PORT = int(os.getenv("PORT", "8502"))


class DashboardHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Keep terminal output clean and readable
        sys.stdout.write(f"[EventOps] {self.address_string()} - {format % args}\n")

    def _send_json(self, status, payload):
        body = json.dumps(payload, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html_bytes):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html_bytes)))
        self.end_headers()
        self.wfile.write(html_bytes)

    def _read_json_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0:
            return {}
        raw = self.rfile.read(length).decode("utf-8")
        return json.loads(raw)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path in ("/", "/index.html"):
            with open(TEMPLATE_PATH, "rb") as f:
                self._send_html(f.read())
            return
        if parsed.path == "/api/overview":
            try:
                self._send_json(200, db_engine.get_dashboard_snapshot())
            except Exception as exc:
                self._send_json(500, {"error": str(exc)})
            return
        if parsed.path == "/api/health":
            self._send_json(200, {"status": "ok", "db": db_engine.DB_PATH})
            return
        self._send_json(404, {"error": "Endpoint not found"})

    def do_POST(self):
        parsed = urlparse(self.path)
        try:
            data = self._read_json_body()
            if parsed.path == "/api/register":
                res = db_engine.register_attendee_atomic(
                    int(data["event_id"]),
                    int(data["attendee_id"]),
                    int(data["ticket_type_id"]),
                    data.get("payment_method", "UPI"),
                )
                self._send_json(200, res)
            elif parsed.path == "/api/cancel":
                res = db_engine.cancel_and_promote_waitlist(
                    int(data["registration_id"]),
                    data.get("reason", "Attendee schedule conflict"),
                )
                self._send_json(200, res)
            elif parsed.path == "/api/sessions":
                res = db_engine.schedule_session(
                    int(data["event_id"]),
                    int(data["room_id"]),
                    int(data["speaker_id"]),
                    data["session_code"],
                    data["session_title"],
                    data.get("session_type", "Technical_Talk"),
                    data["start_time"],
                    data["end_time"],
                    int(data["session_capacity"]),
                )
                self._send_json(200, res)
            elif parsed.path == "/api/checkin":
                res = db_engine.checkin_attendee(
                    int(data["registration_id"]),
                    int(data["session_id"]),
                    data.get("method", "QR_Scan"),
                )
                self._send_json(200, res)
            elif parsed.path == "/api/events":
                res = db_engine.create_event(
                    data["event_code"],
                    data["event_name"],
                    data.get("event_type", "Conference"),
                    int(data["venue_id"]),
                    data["start_date"],
                    data["end_date"],
                    int(data["total_capacity"]),
                    float(data.get("base_expense_inr", 0)),
                )
                self._send_json(200, res)
            elif parsed.path == "/api/attendees":
                res = db_engine.create_attendee(
                    data["full_name"],
                    data["email"],
                    data["phone"],
                    data["organization"],
                    data["designation"],
                    data["city"],
                )
                self._send_json(200, res)
            elif parsed.path == "/api/sponsors":
                res = db_engine.create_sponsor(
                    int(data["event_id"]),
                    data["sponsor_name"],
                    data["tier"],
                    float(data["contribution_inr"]),
                    data["contact_person"],
                )
                self._send_json(200, res)
            elif parsed.path == "/api/ticket-types":
                res = db_engine.create_ticket_type(
                    int(data["event_id"]),
                    data["category_name"],
                    float(data["price_inr"]),
                    int(data["allocated_seats"]),
                )
                self._send_json(200, res)
            elif parsed.path == "/api/concurrency-test":
                res = db_engine.run_concurrency_stress_test(
                    int(data.get("event_id", 1)),
                    int(data.get("ticket_type_id", 2)),
                    int(data.get("num_threads", 6)),
                )
                self._send_json(200, res)
            elif parsed.path == "/api/reset":
                db_engine.init_db(force_reset=True)
                self._send_json(200, {"message": "Database reset successfully."})
            else:
                self._send_json(404, {"error": "Endpoint not found"})
        except Exception as exc:
            self._send_json(400, {"error": str(exc)})


def run_server(port=DEFAULT_PORT, open_browser=True):
    db_engine.init_db(force_reset=False)
    server = ThreadingHTTPServer(("127.0.0.1", port), DashboardHandler)
    url = f"http://localhost:{port}"
    print("=" * 64)
    print("  🎟️  EventOps Web Dashboard — Shreya Adhikari (TCA2573041)")
    print(f"  🌐  Open in browser: {url}")
    print(f"  🗄️  SQLite Database: {db_engine.DB_PATH}")
    print("  ⏹️  Press Ctrl+C to stop the server")
    print("=" * 64)
    if open_browser:
        threading.Timer(0.8, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down EventOps Web Dashboard...")
    finally:
        server.server_close()


if __name__ == "__main__":
    no_browser = "--no-browser" in sys.argv
    port = DEFAULT_PORT
    for arg in sys.argv[1:]:
        if arg.startswith("--port="):
            port = int(arg.split("=", 1)[1])
    run_server(port=port, open_browser=not no_browser)

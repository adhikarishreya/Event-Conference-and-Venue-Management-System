"""
Event, Conference and Venue Management System - Database Engine
Team: Shreya Adhikari (TCA2573041)

Zero-dependency SQLite 3 backend (with WAL + BEGIN IMMEDIATE ACID locking)
that mirrors sql/init.sql (MySQL 8.0+) 1-to-1 for instant execution on macOS.
"""

import hashlib
import os
import random
import sqlite3
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "event_ops.db")
INIT_SQL_PATH = os.path.join(BASE_DIR, "sql", "init_sqlite.sql")

# Process-wide lock to serialize SQLite write transactions cleanly under heavy thread bursts
_WRITE_LOCK = threading.RLock()


def get_connection():
    conn = sqlite3.connect(DB_PATH, timeout=30.0, isolation_level=None, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.execute("PRAGMA journal_mode = WAL;")
    return conn


def init_db(force_reset=False):
    """Initialize event_ops.db from sql/init_sqlite.sql if missing or reset requested."""
    with _WRITE_LOCK:
        if not force_reset and os.path.exists(DB_PATH) and os.path.getsize(DB_PATH) > 0:
            return
        if not os.path.exists(INIT_SQL_PATH):
            raise FileNotFoundError(f"Missing schema file: {INIT_SQL_PATH}")
        with open(INIT_SQL_PATH, "r", encoding="utf-8") as f:
            sql_script = f.read()
        conn = get_connection()
        try:
            conn.executescript(sql_script)
        finally:
            conn.close()


def query_all(sql, params=()):
    conn = get_connection()
    try:
        rows = conn.execute(sql, params).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def query_one(sql, params=()):
    conn = get_connection()
    try:
        row = conn.execute(sql, params).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_dashboard_snapshot():
    """Return all tables and analytical views needed by the web dashboard."""
    events_board = query_all("SELECT * FROM vw_event_financial_and_capacity ORDER BY event_id")
    for ev in events_board:
        total_rev = float(ev["ticket_revenue_inr"]) + float(ev["sponsor_revenue_inr"])
        ev["total_revenue_inr"] = total_rev
        ev["net_profit_inr"] = total_rev - float(ev["total_expense_inr"])
        conf = int(ev["confirmed_count"])
        ev["occupancy_pct"] = round((conf / ev["total_capacity"]) * 100, 1) if ev["total_capacity"] else 0.0
        ev["participation_rate_pct"] = round((ev["checked_in_count"] / conf) * 100, 1) if conf else 0.0

    sessions = query_all("SELECT * FROM vw_session_schedule_board ORDER BY start_time")
    registrations = query_all(
        """
        SELECT r.registration_id, r.reg_code, r.event_id, e.event_code, e.event_name,
               r.attendee_id, a.full_name, a.email, a.organization,
               r.ticket_type_id, tt.category_name, tt.price_inr,
               r.registration_status, r.waitlist_position, r.registered_at,
               t.ticket_number, t.issue_status AS ticket_status,
               p.transaction_ref, p.payment_method, p.payment_status
        FROM REGISTRATION r
        JOIN EVENT e ON r.event_id = e.event_id
        JOIN ATTENDEE a ON r.attendee_id = a.attendee_id
        JOIN TICKET_TYPE tt ON r.ticket_type_id = tt.ticket_type_id
        LEFT JOIN TICKET t ON t.registration_id = r.registration_id
        LEFT JOIN PAYMENT p ON p.registration_id = r.registration_id
        ORDER BY r.registration_id DESC
        """
    )
    certificates = query_all("SELECT * FROM vw_attendance_certificates ORDER BY checkin_time DESC")
    refunds = query_all(
        """
        SELECT rf.*, r.reg_code, a.full_name AS attendee_name, e.event_code
        FROM REFUND rf
        JOIN REGISTRATION r ON rf.registration_id = r.registration_id
        JOIN ATTENDEE a ON r.attendee_id = a.attendee_id
        JOIN EVENT e ON r.event_id = e.event_id
        ORDER BY rf.refund_id DESC
        """
    )
    sponsors = query_all(
        """
        SELECT s.*, e.event_code, e.event_name
        FROM SPONSOR s
        JOIN EVENT e ON s.event_id = e.event_id
        ORDER BY s.contribution_inr DESC
        """
    )
    ticket_types = query_all(
        """
        SELECT tt.*, e.event_code, e.event_name
        FROM TICKET_TYPE tt
        JOIN EVENT e ON tt.event_id = e.event_id
        ORDER BY tt.event_id, tt.price_inr
        """
    )
    venues = query_all("SELECT * FROM VENUE ORDER BY venue_id")
    rooms = query_all(
        """
        SELECT r.*, v.venue_name, v.city
        FROM ROOM r JOIN VENUE v ON r.venue_id = v.venue_id
        ORDER BY r.room_id
        """
    )
    speakers = query_all("SELECT * FROM SPEAKER ORDER BY speaker_id")
    attendees = query_all("SELECT * FROM ATTENDEE ORDER BY attendee_id")
    payments = query_all(
        """
        SELECT p.*, r.reg_code, a.full_name AS attendee_name, e.event_code
        FROM PAYMENT p
        JOIN REGISTRATION r ON p.registration_id = r.registration_id
        JOIN ATTENDEE a ON r.attendee_id = a.attendee_id
        JOIN EVENT e ON r.event_id = e.event_id
        ORDER BY p.payment_id DESC
        """
    )

    return {
        "engine": "SQLite 3 (WAL + BEGIN IMMEDIATE ACID Locking)",
        "mysql_script": "sql/init.sql",
        "events": events_board,
        "sessions": sessions,
        "registrations": registrations,
        "certificates": certificates,
        "refunds": refunds,
        "payments": payments,
        "sponsors": sponsors,
        "ticket_types": ticket_types,
        "venues": venues,
        "rooms": rooms,
        "speakers": speakers,
        "attendees": attendees,
    }


def register_attendee_atomic(event_id, attendee_id, ticket_type_id, payment_method="UPI"):
    """
    Mirrors MySQL stored procedure `sp_register_attendee_atomic`.
    Uses BEGIN IMMEDIATE pessimistic write locking to prevent capacity overselling
    and duplicate registrations under concurrent final-seat contention.
    """
    with _WRITE_LOCK:
        conn = get_connection()
        try:
            conn.execute("BEGIN IMMEDIATE")

            # 1. Prevent duplicate active registration for same event
            dup = conn.execute(
                """
                SELECT registration_id, registration_status
                FROM REGISTRATION
                WHERE event_id = ? AND attendee_id = ?
                """,
                (event_id, attendee_id),
            ).fetchone()
            if dup is not None:
                if dup["registration_status"] != "Cancelled":
                    raise ValueError("DUPLICATE BLOCKED: Attendee is already registered or waitlisted for this event.")
                # If previously cancelled, remove old cancelled row or block re-registration cleanly
                raise ValueError("DUPLICATE BLOCKED: Attendee already has a registration record for this event (unique constraint uq_event_attendee).")

            # 2. Read & lock EVENT and TICKET_TYPE
            ev = conn.execute(
                "SELECT event_code, total_capacity, confirmed_count, waitlist_count FROM EVENT WHERE event_id = ?",
                (event_id,),
            ).fetchone()
            if not ev:
                raise ValueError("Selected event does not exist.")

            tt = conn.execute(
                "SELECT category_name, allocated_seats, sold_seats, price_inr FROM TICKET_TYPE WHERE ticket_type_id = ? AND event_id = ?",
                (ticket_type_id, event_id),
            ).fetchone()
            if not tt:
                raise ValueError("Selected ticket category does not belong to the chosen event.")

            reg_code = f"REG-{event_id}-{attendee_id}-{random.randint(100, 999)}"
            ts = int(time.time() * 1000) % 1000000

            if ev["confirmed_count"] < ev["total_capacity"] and tt["sold_seats"] < tt["allocated_seats"]:
                cur = conn.execute(
                    """
                    INSERT INTO REGISTRATION (reg_code, event_id, attendee_id, ticket_type_id, registration_status, waitlist_position)
                    VALUES (?, ?, ?, ?, 'Confirmed', NULL)
                    """,
                    (reg_code, event_id, attendee_id, ticket_type_id),
                )
                reg_id = cur.lastrowid

                conn.execute("UPDATE EVENT SET confirmed_count = confirmed_count + 1 WHERE event_id = ?", (event_id,))
                conn.execute("UPDATE TICKET_TYPE SET sold_seats = sold_seats + 1 WHERE ticket_type_id = ?", (ticket_type_id,))

                qr_hash = hashlib.sha256(f"{reg_code}-{ts}-{random.random()}".encode()).hexdigest()
                ticket_no = f"TKT-{reg_id}-{event_id:02d}"
                conn.execute(
                    """
                    INSERT INTO TICKET (ticket_number, registration_id, ticket_type_id, qr_code_hash)
                    VALUES (?, ?, ?, ?)
                    """,
                    (ticket_no, reg_id, ticket_type_id, qr_hash),
                )
                txn_ref = f"TXN-{reg_id}-{ts}"
                conn.execute(
                    """
                    INSERT INTO PAYMENT (transaction_ref, registration_id, amount_inr, payment_method, payment_status)
                    VALUES (?, ?, ?, ?, 'Paid')
                    """,
                    (txn_ref, reg_id, tt["price_inr"], payment_method),
                )
                conn.execute("COMMIT")
                return {
                    "status": "Confirmed",
                    "reg_code": reg_code,
                    "ticket_number": ticket_no,
                    "transaction_ref": txn_ref,
                    "message": f"CONFIRMED ({reg_code}) — Ticket {ticket_no} issued via {payment_method}",
                }
            else:
                new_pos = ev["waitlist_count"] + 1
                conn.execute("UPDATE EVENT SET waitlist_count = waitlist_count + 1 WHERE event_id = ?", (event_id,))
                conn.execute(
                    """
                    INSERT INTO REGISTRATION (reg_code, event_id, attendee_id, ticket_type_id, registration_status, waitlist_position)
                    VALUES (?, ?, ?, ?, 'Waitlisted', ?)
                    """,
                    (reg_code, event_id, attendee_id, ticket_type_id, new_pos),
                )
                conn.execute("COMMIT")
                return {
                    "status": "Waitlisted",
                    "reg_code": reg_code,
                    "waitlist_position": new_pos,
                    "message": f"WAITLISTED #{new_pos} ({reg_code}) — Event/Tier at full capacity",
                }
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()


def cancel_and_promote_waitlist(registration_id, reason="Attendee schedule conflict"):
    """
    Mirrors MySQL stored procedure `sp_cancel_and_promote_waitlist`.
    Cancels registration, voids ticket, issues refund, and auto-promotes #1 waitlisted attendee.
    """
    with _WRITE_LOCK:
        conn = get_connection()
        try:
            conn.execute("BEGIN IMMEDIATE")
            reg = conn.execute(
                "SELECT event_id, ticket_type_id, registration_status, reg_code FROM REGISTRATION WHERE registration_id = ?",
                (registration_id,),
            ).fetchone()
            if not reg:
                raise ValueError("Registration not found.")
            if reg["registration_status"] == "Cancelled":
                raise ValueError("Registration is already cancelled.")

            event_id = reg["event_id"]
            tt_id = reg["ticket_type_id"]
            prev_status = reg["registration_status"]

            conn.execute("UPDATE REGISTRATION SET registration_status = 'Cancelled', waitlist_position = NULL WHERE registration_id = ?", (registration_id,))
            conn.execute("UPDATE TICKET SET issue_status = 'Voided' WHERE registration_id = ?", (registration_id,))

            promoted_info = None
            refund_ref = None

            if prev_status == "Waitlisted":
                conn.execute("UPDATE EVENT SET waitlist_count = MAX(waitlist_count - 1, 0) WHERE event_id = ?", (event_id,))
            elif prev_status in ("Confirmed", "Checked_In"):
                pay = conn.execute(
                    "SELECT payment_id, amount_inr FROM PAYMENT WHERE registration_id = ? LIMIT 1",
                    (registration_id,),
                ).fetchone()
                if pay:
                    ts = int(time.time() * 1000) % 1000000
                    refund_ref = f"RFD-{registration_id}-{ts}"
                    conn.execute("UPDATE PAYMENT SET payment_status = 'Refunded' WHERE payment_id = ?", (pay["payment_id"],))
                    conn.execute(
                        """
                        INSERT INTO REFUND (refund_ref, payment_id, registration_id, refund_amount_inr, refund_reason)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                        (refund_ref, pay["payment_id"], registration_id, pay["amount_inr"], reason),
                    )

                conn.execute("UPDATE EVENT SET confirmed_count = MAX(confirmed_count - 1, 0) WHERE event_id = ?", (event_id,))
                conn.execute("UPDATE TICKET_TYPE SET sold_seats = MAX(sold_seats - 1, 0) WHERE ticket_type_id = ?", (tt_id,))

                # Promote earliest waitlisted attendee for this event
                nxt = conn.execute(
                    """
                    SELECT r.registration_id, r.reg_code, r.ticket_type_id, a.full_name
                    FROM REGISTRATION r
                    JOIN ATTENDEE a ON r.attendee_id = a.attendee_id
                    WHERE r.event_id = ? AND r.registration_status = 'Waitlisted'
                    ORDER BY r.waitlist_position ASC, r.registered_at ASC
                    LIMIT 1
                    """,
                    (event_id,),
                ).fetchone()

                if nxt:
                    nxt_tt = conn.execute("SELECT price_inr, sold_seats, allocated_seats FROM TICKET_TYPE WHERE ticket_type_id = ?", (nxt["ticket_type_id"],)).fetchone()
                    promo_tt_id = nxt["ticket_type_id"] if nxt_tt["sold_seats"] < nxt_tt["allocated_seats"] else tt_id
                    promo_price = conn.execute("SELECT price_inr FROM TICKET_TYPE WHERE ticket_type_id = ?", (promo_tt_id,)).fetchone()["price_inr"]

                    conn.execute(
                        "UPDATE REGISTRATION SET registration_status = 'Confirmed', waitlist_position = NULL, ticket_type_id = ? WHERE registration_id = ?",
                        (promo_tt_id, nxt["registration_id"]),
                    )
                    conn.execute(
                        "UPDATE EVENT SET confirmed_count = confirmed_count + 1, waitlist_count = MAX(waitlist_count - 1, 0) WHERE event_id = ?",
                        (event_id,),
                    )
                    conn.execute("UPDATE TICKET_TYPE SET sold_seats = sold_seats + 1 WHERE ticket_type_id = ?", (promo_tt_id,))

                    ts2 = int(time.time() * 1000) % 1000000
                    qr_hash = hashlib.sha256(f"{nxt['registration_id']}-PROMO-{ts2}-{random.random()}".encode()).hexdigest()
                    conn.execute(
                        """
                        INSERT INTO TICKET (ticket_number, registration_id, ticket_type_id, qr_code_hash)
                        VALUES (?, ?, ?, ?)
                        """,
                        (f"TKT-{nxt['registration_id']}-PROMO", nxt["registration_id"], promo_tt_id, qr_hash),
                    )
                    conn.execute(
                        """
                        INSERT INTO PAYMENT (transaction_ref, registration_id, amount_inr, payment_method, payment_status)
                        VALUES (?, ?, ?, 'UPI', 'Paid')
                        """,
                        (f"TXN-PROMO-{nxt['registration_id']}-{ts2}", nxt["registration_id"], promo_price),
                    )
                    promoted_info = f"{nxt['full_name']} ({nxt['reg_code']})"

            conn.execute("COMMIT")
            msg = f"Cancelled {reg['reg_code']}."
            if refund_ref:
                msg += f" Refund {refund_ref} processed."
            if promoted_info:
                msg += f" Auto-promoted from waitlist: {promoted_info}."
            return {"message": msg, "refund_ref": refund_ref, "promoted": promoted_info}
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()


def schedule_session(event_id, room_id, speaker_id, session_code, session_title, session_type, start_time, end_time, session_capacity):
    """Insert a session; SQLite triggers enforce maintenance, room capacity, 15-min room buffer, and speaker overlap."""
    with _WRITE_LOCK:
        conn = get_connection()
        try:
            conn.execute("BEGIN IMMEDIATE")
            conn.execute(
                """
                INSERT INTO SESSION (event_id, room_id, speaker_id, session_code, session_title, session_type, start_time, end_time, session_capacity)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (event_id, room_id, speaker_id, session_code.strip(), session_title.strip(), session_type, start_time.strip(), end_time.strip(), int(session_capacity)),
            )
            conn.execute("COMMIT")
            return {"message": f"Session {session_code} scheduled successfully."}
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()


def checkin_attendee(registration_id, session_id, method="QR_Scan"):
    """Check in a confirmed attendee to a session and issue an attendance certificate."""
    with _WRITE_LOCK:
        conn = get_connection()
        try:
            conn.execute("BEGIN IMMEDIATE")
            reg = conn.execute(
                "SELECT registration_status, event_id FROM REGISTRATION WHERE registration_id = ?",
                (registration_id,),
            ).fetchone()
            if not reg or reg["registration_status"] not in ("Confirmed", "Checked_In"):
                raise ValueError("Only Confirmed attendees can check in to sessions.")

            sess = conn.execute("SELECT event_id, session_code FROM SESSION WHERE session_id = ?", (session_id,)).fetchone()
            if not sess:
                raise ValueError("Selected session not found.")
            if sess["event_id"] != reg["event_id"]:
                raise ValueError("Attendee is not registered for this session's event.")

            cert_code = f"CERT-{sess['session_code']}-{registration_id:04d}-{random.randint(10, 99)}"
            conn.execute(
                """
                INSERT INTO CHECK_IN (registration_id, session_id, checkin_method, certificate_code, certificate_issued)
                VALUES (?, ?, ?, ?, 1)
                """,
                (registration_id, session_id, method, cert_code),
            )
            conn.execute("UPDATE REGISTRATION SET registration_status = 'Checked_In' WHERE registration_id = ?", (registration_id,))
            conn.execute("UPDATE TICKET SET issue_status = 'Used' WHERE registration_id = ? AND issue_status = 'Active'", (registration_id,))
            conn.execute("COMMIT")
            return {"message": f"Check-in recorded! Certificate {cert_code} issued.", "certificate_code": cert_code}
        except sqlite3.IntegrityError as exc:
            conn.execute("ROLLBACK")
            if "UNIQUE" in str(exc):
                raise ValueError("Attendee is already checked in to this session.")
            raise
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()


def create_event(event_code, event_name, event_type, venue_id, start_date, end_date, total_capacity, base_expense_inr):
    with _WRITE_LOCK:
        conn = get_connection()
        try:
            conn.execute("BEGIN IMMEDIATE")
            cur = conn.execute(
                """
                INSERT INTO EVENT (event_code, event_name, event_type, venue_id, start_date, end_date, total_capacity, base_expense_inr)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (event_code.strip(), event_name.strip(), event_type, int(venue_id), start_date, end_date, int(total_capacity), float(base_expense_inr)),
            )
            ev_id = cur.lastrowid
            # Create a default General Admission ticket category so it's immediately registrable
            conn.execute(
                """
                INSERT INTO TICKET_TYPE (event_id, category_name, price_inr, allocated_seats, sold_seats)
                VALUES (?, 'General Pass', 2000.00, ?, 0)
                """,
                (ev_id, int(total_capacity)),
            )
            conn.execute("COMMIT")
            return {"message": f"Event {event_code} created with default General Pass.", "event_id": ev_id}
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()


def create_attendee(full_name, email, phone, organization, designation, city):
    with _WRITE_LOCK:
        conn = get_connection()
        try:
            conn.execute("BEGIN IMMEDIATE")
            cur = conn.execute(
                """
                INSERT INTO ATTENDEE (full_name, email, phone, organization, designation, city)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (full_name.strip(), email.strip(), phone.strip(), organization.strip(), designation.strip(), city.strip()),
            )
            conn.execute("COMMIT")
            return {"message": f"Attendee {full_name} added.", "attendee_id": cur.lastrowid}
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()


def create_sponsor(event_id, sponsor_name, tier, contribution_inr, contact_person, sponsorship_status="Received"):
    with _WRITE_LOCK:
        conn = get_connection()
        try:
            conn.execute("BEGIN IMMEDIATE")
            conn.execute(
                """
                INSERT INTO SPONSOR (event_id, sponsor_name, tier, contribution_inr, contact_person, sponsorship_status)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (int(event_id), sponsor_name.strip(), tier, float(contribution_inr), contact_person.strip(), sponsorship_status),
            )
            conn.execute("COMMIT")
            return {"message": f"Sponsor {sponsor_name} added."}
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()


def create_ticket_type(event_id, category_name, price_inr, allocated_seats):
    with _WRITE_LOCK:
        conn = get_connection()
        try:
            conn.execute("BEGIN IMMEDIATE")
            conn.execute(
                """
                INSERT INTO TICKET_TYPE (event_id, category_name, price_inr, allocated_seats, sold_seats)
                VALUES (?, ?, ?, ?, 0)
                """,
                (int(event_id), category_name.strip(), float(price_inr), int(allocated_seats)),
            )
            conn.execute("COMMIT")
            return {"message": f"Ticket category '{category_name}' added."}
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()


def run_concurrency_stress_test(event_id=1, ticket_type_id=2, num_threads=6):
    """
    Advanced Challenge Simulator:
    Creates temporary contenders (plus one intentional duplicate) and fires simultaneous
    threads competing for the final remaining seat(s) using a threading.Barrier so all
    threads hit register_attendee_atomic at the exact same millisecond.
    """
    ts = int(time.time() * 1000) % 100000
    contenders = []
    # Create fresh test attendees so the race can be run repeatedly
    for i in range(1, num_threads):
        name = f"Race Contender #{i}"
        email = f"race_{ts}_{i}@sim.eventops.in"
        res = create_attendee(name, email, f"98000{ts % 10000:04d}{i}", "ConcurrencyLab", "Test Attendee", "New Delhi")
        contenders.append((f"Thread-{i}", res["attendee_id"], name))

    # Add an intentional duplicate thread using the first contender's ID
    dup_target = contenders[0]
    contenders.append((f"Thread-{num_threads} (Duplicate)", dup_target[1], f"{dup_target[2]} [DUP]"))

    barrier = threading.Barrier(len(contenders))
    results = []

    def worker(thread_label, att_id, att_name):
        barrier.wait()  # Release all threads simultaneously!
        t0 = time.perf_counter()
        try:
            outcome = register_attendee_atomic(event_id, att_id, ticket_type_id, "UPI")
            elapsed_ms = round((time.perf_counter() - t0) * 1000, 2)
            return {
                "thread": thread_label,
                "attendee": att_name,
                "outcome": outcome["status"],
                "detail": outcome["message"],
                "elapsed_ms": elapsed_ms,
            }
        except Exception as exc:
            elapsed_ms = round((time.perf_counter() - t0) * 1000, 2)
            return {
                "thread": thread_label,
                "attendee": att_name,
                "outcome": "Blocked",
                "detail": str(exc),
                "elapsed_ms": elapsed_ms,
            }

    with ThreadPoolExecutor(max_workers=len(contenders)) as pool:
        futures = [pool.submit(worker, *c) for c in contenders]
        for f in futures:
            results.append(f.result())

    ev_after = query_one("SELECT event_code, total_capacity, confirmed_count, waitlist_count FROM EVENT WHERE event_id = ?", (event_id,))
    confirmed = sum(1 for r in results if r["outcome"] == "Confirmed")
    waitlisted = sum(1 for r in results if r["outcome"] == "Waitlisted")
    blocked = sum(1 for r in results if r["outcome"] == "Blocked")
    capacity_ok = ev_after["confirmed_count"] <= ev_after["total_capacity"]

    return {
        "event": ev_after,
        "summary": {
            "total_threads": len(contenders),
            "confirmed": confirmed,
            "waitlisted": waitlisted,
            "blocked_duplicates": blocked,
            "capacity_integrity_passed": capacity_ok,
        },
        "results": results,
    }

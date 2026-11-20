# Event, Conference & Venue Management System

**Team:** Shreya Adhikari (`TCA2573041`)  
**Syllabus Coverage:** ER Modeling, Relational Mapping, SQL Joins, Constraints, Triggers & Stored Procedures (PL/SQL), ACID Transactions, Concurrency Control, and Analytical Reporting.

---

## Option 1: Instant macOS Web Dashboard (Zero Installs Required)

Runs immediately on macOS using Python 3's built-in `sqlite3` and `http.server` — no Docker, MySQL, or `pip install` needed. It mirrors all 13 tables, triggers, analytical views, and ACID concurrency locking from `sql/init.sql`.

### Launch via Finder (Easiest)
Double-click **`start_dashboard.command`** inside this folder. Your browser will open automatically at `http://localhost:8502`.

### Launch via Terminal
```bash
cd /Users/jayendrajain/Downloads/shreya/event_conference_management_system
python3 dashboard.py
```
Then open **`http://localhost:8502`** in Safari or Chrome. Press `Ctrl + C` in Terminal to stop the server.

### What's Connected in the Web Dashboard
- **📊 Event Board & P&L:** KPI metrics, SVG bar charts (Capacity vs. Waitlist and Revenue vs. Expenses), occupancy & participation rates (`vw_event_financial_and_capacity`), and Create Event form.
- **⚡ Seat & Waitlist Lab (Advanced Challenge):** Atomic attendee registration (`BEGIN IMMEDIATE` pessimistic locking), duplicate registration guard, automatic waitlist queueing, and a **1-Click 6-Thread Concurrency Simulator** competing for the final seat in `CONF-AI-26`.
- **🏛️ Sessions & Conflict Guard:** Conference schedule (`vw_session_schedule_board`) and session scheduler backed by SQL triggers enforcing room maintenance, room capacity limits, **15-minute room turnover buffers**, and speaker overlap checks (with a 1-click conflict test button).
- **💳 Payments, Cancellations & Refunds:** Cancel confirmed registrations to void tickets, record refunds in `REFUND`, and **auto-promote** the #1 waitlisted attendee with a new ticket and payment.
- **🎫 Check-In & Certificates:** Record session check-ins and open a **printable / PDF Attendance Certificate** (`vw_attendance_certificates`).
- **🤝 Sponsors, Venues & Ticket Categories:** View and add event sponsors, ticket tiers, and inspect venue rooms.
- **♻️ Reset Demo DB:** One-click button in the sidebar to restore clean initial seed data anytime during a presentation or viva.

---

## Option 2: Docker + MySQL 8.0 + Streamlit Stack

If you have Docker Desktop installed on macOS, you can also run the MySQL 8.0 + Streamlit stack:

```bash
docker compose up -d --build
```
- **Streamlit Dashboard:** `http://localhost:8502`
- **MySQL 8.0 Server:** `localhost:3307` (`user: root`, `password: rootpassword123`, `database: event_ops_db`)

---

## Project Files
- `dashboard.py` — Zero-dependency macOS web server & REST API (`http://localhost:8502`).
- `db_engine.py` — ACID SQLite 3 database engine mirroring MySQL stored procedures (`sp_register_attendee_atomic`, `sp_cancel_and_promote_waitlist`) + 6-thread concurrency simulator.
- `templates/index.html` — Responsive web dashboard UI with interactive charts and printable certificates.
- `start_dashboard.command` — Double-clickable macOS launcher.
- `sql/init_sqlite.sql` — SQLite 3 mirror of the 13-table schema, triggers, views, and seed data.
- `sql/init.sql` — MySQL 8.0 DDL, triggers, stored procedures, views, and seed data.
- `app.py`, `Dockerfile`, `docker-compose.yml`, `requirements.txt` — Optional Docker/Streamlit/MySQL stack.

## 13 Core Tables
1. `VENUE` — Conference centers, total capacity, and rental costs.
2. `ROOM` — Auditoriums, halls, and workshop rooms with AV specs.
3. `EVENT` — Conferences/workshops with capacity, confirmed, and waitlist counters.
4. `SPEAKER` — Keynote and workshop speakers with honorariums.
5. `SESSION` — Scheduled talks/workshops with room and speaker conflict guards.
6. `ATTENDEE` — Registered participants and organizations.
7. `TICKET_TYPE` — Early Bird, VIP, Student, and Workshop ticket tiers.
8. `REGISTRATION` — Confirmed, waitlisted, and cancelled registrations (duplicate-protected).
9. `TICKET` — Issued e-tickets with SHA-256 QR hashes.
10. `PAYMENT` — Ticket payment records and transaction references.
11. `REFUND` — Cancellation refunds linked to payments.
12. `CHECK_IN` — Session attendance check-ins and certificate codes.
13. `SPONSOR` — Event sponsors, tiers, and financial contributions.

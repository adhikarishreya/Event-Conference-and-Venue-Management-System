-- ============================================================================
-- EVENT, CONFERENCE AND VENUE MANAGEMENT SYSTEM (SQLite 3 Local Mirror)
-- Mirrors sql/init.sql (MySQL 8.0+) for zero-dependency macOS execution
-- Team: Shreya Adhikari (TCA2573041)
-- ============================================================================

PRAGMA foreign_keys = OFF;

DROP VIEW IF EXISTS vw_attendance_certificates;
DROP VIEW IF EXISTS vw_session_schedule_board;
DROP VIEW IF EXISTS vw_event_financial_and_capacity;

DROP TABLE IF EXISTS SPONSOR;
DROP TABLE IF EXISTS CHECK_IN;
DROP TABLE IF EXISTS REFUND;
DROP TABLE IF EXISTS PAYMENT;
DROP TABLE IF EXISTS TICKET;
DROP TABLE IF EXISTS REGISTRATION;
DROP TABLE IF EXISTS TICKET_TYPE;
DROP TABLE IF EXISTS ATTENDEE;
DROP TABLE IF EXISTS SESSION;
DROP TABLE IF EXISTS SPEAKER;
DROP TABLE IF EXISTS EVENT;
DROP TABLE IF EXISTS ROOM;
DROP TABLE IF EXISTS VENUE;

PRAGMA foreign_keys = ON;

-- ============================================================================
-- 1. CORE TABLES (13 Tables)
-- ============================================================================

CREATE TABLE VENUE (
    venue_id INTEGER PRIMARY KEY AUTOINCREMENT,
    venue_name TEXT NOT NULL UNIQUE,
    city TEXT NOT NULL,
    address TEXT NOT NULL,
    total_capacity INTEGER NOT NULL CHECK (total_capacity > 0),
    contact_email TEXT NOT NULL,
    rental_cost_inr REAL NOT NULL DEFAULT 0.00
);

CREATE TABLE ROOM (
    room_id INTEGER PRIMARY KEY AUTOINCREMENT,
    venue_id INTEGER NOT NULL,
    room_code TEXT NOT NULL UNIQUE,
    room_name TEXT NOT NULL,
    room_type TEXT NOT NULL CHECK (room_type IN ('Main_Auditorium', 'Conference_Hall', 'Workshop_Lab', 'Boardroom')),
    max_capacity INTEGER NOT NULL CHECK (max_capacity > 0),
    has_av_system INTEGER NOT NULL DEFAULT 1 CHECK (has_av_system IN (0, 1)),
    room_status TEXT NOT NULL DEFAULT 'Available' CHECK (room_status IN ('Available', 'Maintenance', 'Reserved')),
    FOREIGN KEY (venue_id) REFERENCES VENUE(venue_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE EVENT (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_code TEXT NOT NULL UNIQUE,
    event_name TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('Conference', 'Workshop', 'Summit', 'Hackathon')),
    venue_id INTEGER NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    total_capacity INTEGER NOT NULL,
    confirmed_count INTEGER NOT NULL DEFAULT 0,
    waitlist_count INTEGER NOT NULL DEFAULT 0,
    base_expense_inr REAL NOT NULL DEFAULT 0.00,
    event_status TEXT NOT NULL DEFAULT 'Upcoming' CHECK (event_status IN ('Upcoming', 'Ongoing', 'Completed', 'Cancelled')),
    FOREIGN KEY (venue_id) REFERENCES VENUE(venue_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (end_date >= start_date),
    CHECK (total_capacity > 0 AND confirmed_count >= 0 AND confirmed_count <= total_capacity AND waitlist_count >= 0)
);

CREATE TABLE SPEAKER (
    speaker_id INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name TEXT NOT NULL,
    organization TEXT NOT NULL,
    expertise_area TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    honorarium_inr REAL NOT NULL DEFAULT 0.00,
    speaker_status TEXT NOT NULL DEFAULT 'Confirmed' CHECK (speaker_status IN ('Confirmed', 'Invited', 'Unavailable'))
);

CREATE TABLE SESSION (
    session_id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER NOT NULL,
    room_id INTEGER NOT NULL,
    speaker_id INTEGER NOT NULL,
    session_code TEXT NOT NULL UNIQUE,
    session_title TEXT NOT NULL,
    session_type TEXT NOT NULL CHECK (session_type IN ('Keynote', 'Technical_Talk', 'Workshop', 'Panel')),
    start_time TEXT NOT NULL,
    end_time TEXT NOT NULL,
    session_capacity INTEGER NOT NULL CHECK (session_capacity > 0),
    session_status TEXT NOT NULL DEFAULT 'Scheduled' CHECK (session_status IN ('Scheduled', 'In_Progress', 'Completed', 'Cancelled')),
    FOREIGN KEY (event_id) REFERENCES EVENT(event_id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (room_id) REFERENCES ROOM(room_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (speaker_id) REFERENCES SPEAKER(speaker_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (end_time > start_time)
);

CREATE TABLE ATTENDEE (
    attendee_id INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    phone TEXT NOT NULL,
    organization TEXT NOT NULL,
    designation TEXT NOT NULL,
    city TEXT NOT NULL
);

CREATE TABLE TICKET_TYPE (
    ticket_type_id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER NOT NULL,
    category_name TEXT NOT NULL,
    price_inr REAL NOT NULL CHECK (price_inr >= 0.00),
    allocated_seats INTEGER NOT NULL,
    sold_seats INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    UNIQUE (event_id, category_name),
    FOREIGN KEY (event_id) REFERENCES EVENT(event_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CHECK (allocated_seats > 0 AND sold_seats >= 0 AND sold_seats <= allocated_seats)
);

CREATE TABLE REGISTRATION (
    registration_id INTEGER PRIMARY KEY AUTOINCREMENT,
    reg_code TEXT NOT NULL UNIQUE,
    event_id INTEGER NOT NULL,
    attendee_id INTEGER NOT NULL,
    ticket_type_id INTEGER NOT NULL,
    registration_status TEXT NOT NULL DEFAULT 'Confirmed' CHECK (registration_status IN ('Confirmed', 'Waitlisted', 'Cancelled', 'Checked_In')),
    waitlist_position INTEGER NULL,
    registered_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    UNIQUE (event_id, attendee_id),
    FOREIGN KEY (event_id) REFERENCES EVENT(event_id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (attendee_id) REFERENCES ATTENDEE(attendee_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (ticket_type_id) REFERENCES TICKET_TYPE(ticket_type_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE TICKET (
    ticket_id INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_number TEXT NOT NULL UNIQUE,
    registration_id INTEGER NOT NULL UNIQUE,
    ticket_type_id INTEGER NOT NULL,
    qr_code_hash TEXT NOT NULL UNIQUE,
    issue_status TEXT NOT NULL DEFAULT 'Active' CHECK (issue_status IN ('Active', 'Used', 'Voided')),
    issued_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    FOREIGN KEY (registration_id) REFERENCES REGISTRATION(registration_id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (ticket_type_id) REFERENCES TICKET_TYPE(ticket_type_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE PAYMENT (
    payment_id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_ref TEXT NOT NULL UNIQUE,
    registration_id INTEGER NOT NULL,
    amount_inr REAL NOT NULL CHECK (amount_inr >= 0.00),
    payment_method TEXT NOT NULL CHECK (payment_method IN ('UPI', 'Credit_Card', 'Debit_Card', 'Net_Banking', 'Corporate_Invoice')),
    payment_status TEXT NOT NULL DEFAULT 'Paid' CHECK (payment_status IN ('Paid', 'Pending', 'Failed', 'Refunded')),
    paid_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    FOREIGN KEY (registration_id) REFERENCES REGISTRATION(registration_id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE REFUND (
    refund_id INTEGER PRIMARY KEY AUTOINCREMENT,
    refund_ref TEXT NOT NULL UNIQUE,
    payment_id INTEGER NOT NULL,
    registration_id INTEGER NOT NULL,
    refund_amount_inr REAL NOT NULL CHECK (refund_amount_inr >= 0.00),
    refund_reason TEXT NOT NULL,
    refund_status TEXT NOT NULL DEFAULT 'Processed' CHECK (refund_status IN ('Processed', 'Pending')),
    processed_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    FOREIGN KEY (payment_id) REFERENCES PAYMENT(payment_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (registration_id) REFERENCES REGISTRATION(registration_id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE CHECK_IN (
    checkin_id INTEGER PRIMARY KEY AUTOINCREMENT,
    registration_id INTEGER NOT NULL,
    session_id INTEGER NOT NULL,
    checkin_time TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    checkin_method TEXT NOT NULL DEFAULT 'QR_Scan' CHECK (checkin_method IN ('QR_Scan', 'Desk_Manual')),
    certificate_code TEXT NOT NULL UNIQUE,
    certificate_issued INTEGER NOT NULL DEFAULT 1 CHECK (certificate_issued IN (0, 1)),
    UNIQUE (registration_id, session_id),
    FOREIGN KEY (registration_id) REFERENCES REGISTRATION(registration_id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES SESSION(session_id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE SPONSOR (
    sponsor_id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER NOT NULL,
    sponsor_name TEXT NOT NULL,
    tier TEXT NOT NULL CHECK (tier IN ('Title', 'Platinum', 'Gold', 'Silver')),
    contribution_inr REAL NOT NULL CHECK (contribution_inr >= 0.00),
    contact_person TEXT NOT NULL,
    sponsorship_status TEXT NOT NULL DEFAULT 'Received' CHECK (sponsorship_status IN ('Confirmed', 'Pledged', 'Received')),
    FOREIGN KEY (event_id) REFERENCES EVENT(event_id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- ============================================================================
-- 2. INDEXES
-- ============================================================================

CREATE INDEX idx_sess_room_window ON SESSION (room_id, start_time, end_time, session_status);
CREATE INDEX idx_sess_speaker_window ON SESSION (speaker_id, start_time, end_time, session_status);
CREATE INDEX idx_reg_event_status ON REGISTRATION (event_id, registration_status, waitlist_position);

-- ============================================================================
-- 3. TRIGGERS (Room Maintenance, Capacity, 15-min Turnover & Speaker Overlap)
-- ============================================================================

CREATE TRIGGER trg_before_session_insert_maintenance
BEFORE INSERT ON SESSION
FOR EACH ROW
WHEN (SELECT room_status FROM ROOM WHERE room_id = NEW.room_id) = 'Maintenance'
BEGIN
    SELECT RAISE(ABORT, 'ROOM CONFLICT: Selected room is under maintenance.');
END;

CREATE TRIGGER trg_before_session_insert_capacity
BEFORE INSERT ON SESSION
FOR EACH ROW
WHEN NEW.session_capacity > (SELECT max_capacity FROM ROOM WHERE room_id = NEW.room_id)
BEGIN
    SELECT RAISE(ABORT, 'CAPACITY CONFLICT: Session capacity exceeds room maximum capacity.');
END;

CREATE TRIGGER trg_before_session_insert_room_overlap
BEFORE INSERT ON SESSION
FOR EACH ROW
WHEN EXISTS (
    SELECT 1 FROM SESSION
    WHERE room_id = NEW.room_id
      AND session_status <> 'Cancelled'
      AND datetime(NEW.start_time) < datetime(end_time, '+15 minutes')
      AND datetime(NEW.end_time) > datetime(start_time, '-15 minutes')
)
BEGIN
    SELECT RAISE(ABORT, 'ROOM CONFLICT: Room is already booked in this window (15-min turnover buffer enforced).');
END;

CREATE TRIGGER trg_before_session_insert_speaker_overlap
BEFORE INSERT ON SESSION
FOR EACH ROW
WHEN EXISTS (
    SELECT 1 FROM SESSION
    WHERE speaker_id = NEW.speaker_id
      AND session_status <> 'Cancelled'
      AND datetime(NEW.start_time) < datetime(end_time)
      AND datetime(NEW.end_time) > datetime(start_time)
)
BEGIN
    SELECT RAISE(ABORT, 'SPEAKER CONFLICT: Speaker is already assigned to an overlapping session.');
END;

-- ============================================================================
-- 4. ANALYTICAL VIEWS
-- ============================================================================

CREATE VIEW vw_event_financial_and_capacity AS
SELECT
    e.event_id,
    e.event_code,
    e.event_name,
    e.event_type,
    v.venue_name,
    v.city,
    e.start_date,
    e.end_date,
    e.event_status,
    e.total_capacity,
    e.confirmed_count,
    (e.total_capacity - e.confirmed_count) AS remaining_seats,
    e.waitlist_count,
    COALESCE((SELECT SUM(p.amount_inr) FROM PAYMENT p JOIN REGISTRATION r ON p.registration_id = r.registration_id WHERE r.event_id = e.event_id AND p.payment_status = 'Paid'), 0.0) AS ticket_revenue_inr,
    COALESCE((SELECT SUM(s.contribution_inr) FROM SPONSOR s WHERE s.event_id = e.event_id), 0.0) AS sponsor_revenue_inr,
    (e.base_expense_inr + v.rental_cost_inr) AS total_expense_inr,
    COALESCE((SELECT COUNT(DISTINCT c.registration_id) FROM CHECK_IN c JOIN REGISTRATION r ON c.registration_id = r.registration_id WHERE r.event_id = e.event_id), 0) AS checked_in_count
FROM EVENT e
JOIN VENUE v ON e.venue_id = v.venue_id;

CREATE VIEW vw_session_schedule_board AS
SELECT
    s.session_id,
    s.session_code,
    e.event_id,
    e.event_code,
    e.event_name,
    s.session_title,
    s.session_type,
    r.room_code,
    r.room_name,
    r.max_capacity AS room_capacity,
    sp.full_name AS speaker_name,
    sp.organization,
    s.start_time,
    s.end_time,
    s.session_capacity,
    s.session_status,
    COALESCE((SELECT COUNT(*) FROM CHECK_IN c WHERE c.session_id = s.session_id), 0) AS attended_count
FROM SESSION s
JOIN EVENT e ON s.event_id = e.event_id
JOIN ROOM r ON s.room_id = r.room_id
JOIN SPEAKER sp ON s.speaker_id = sp.speaker_id;

CREATE VIEW vw_attendance_certificates AS
SELECT
    c.checkin_id,
    c.certificate_code,
    a.full_name AS attendee_name,
    a.email AS attendee_email,
    a.organization,
    e.event_code,
    e.event_name,
    s.session_code,
    s.session_title,
    c.checkin_time,
    c.checkin_method
FROM CHECK_IN c
JOIN REGISTRATION r ON c.registration_id = r.registration_id
JOIN ATTENDEE a ON r.attendee_id = a.attendee_id
JOIN EVENT e ON r.event_id = e.event_id
JOIN SESSION s ON c.session_id = s.session_id;

-- ============================================================================
-- 5. SAMPLE SEED DATA (Exact match with sql/init.sql)
-- ============================================================================

INSERT INTO VENUE (venue_name, city, address, total_capacity, contact_email, rental_cost_inr) VALUES
('Bharat Mandapam Convention Centre', 'New Delhi', 'Pragati Maidan, New Delhi', 1500, 'events@bharatmandapam.in', 250000.00),
('Jio World Convention Centre', 'Mumbai', 'BKC, Bandra East, Mumbai', 1200, 'bookings@jioworld.in', 220000.00);

INSERT INTO ROOM (venue_id, room_code, room_name, room_type, max_capacity, has_av_system, room_status) VALUES
(1, 'BM-AUD1', 'Plenary Hall A', 'Main_Auditorium', 300, 1, 'Available'),
(1, 'BM-WS1', 'AI Workshop Lab 1', 'Workshop_Lab', 60, 1, 'Available'),
(1, 'BM-CONF2', 'Cloud Summit Hall', 'Conference_Hall', 150, 1, 'Available'),
(2, 'JW-AUD1', 'Grand Ballroom', 'Main_Auditorium', 250, 1, 'Available');

INSERT INTO EVENT (event_code, event_name, event_type, venue_id, start_date, end_date, total_capacity, confirmed_count, waitlist_count, base_expense_inr, event_status) VALUES
('CONF-AI-26', 'India AI & Data Engineering Summit 2026', 'Conference', 1, '2026-12-10', '2026-12-11', 5, 4, 0, 120000.00, 'Upcoming'),
('WS-CLD-26', 'Cloud Native & Kubernetes Workshop', 'Workshop', 1, '2026-12-15', '2026-12-15', 40, 2, 0, 45000.00, 'Upcoming');

INSERT INTO SPEAKER (full_name, organization, expertise_area, email, honorarium_inr, speaker_status) VALUES
('Dr. Shreya Adhikari', 'IIT Delhi', 'Distributed Databases & AI', 'shreya.adhikari@iitd.ac.in', 35000.00, 'Confirmed'),
('Rohan Deshmukh', 'CloudScale India', 'Kubernetes & Platform Eng', 'rohan@cloudscale.in', 25000.00, 'Confirmed'),
('Ananya Iyer', 'FinTech Labs', 'Real-time Payments & ACID', 'ananya@fintechlabs.in', 30000.00, 'Confirmed');

INSERT INTO SESSION (event_id, room_id, speaker_id, session_code, session_title, session_type, start_time, end_time, session_capacity) VALUES
(1, 1, 1, 'SESS-101', 'Keynote: Scaling ACID Databases for AI', 'Keynote', '2026-12-10 09:30:00', '2026-12-10 11:00:00', 250),
(1, 2, 2, 'SESS-102', 'Hands-on Kubernetes Operators', 'Workshop', '2026-12-10 11:30:00', '2026-12-10 13:00:00', 55),
(1, 3, 3, 'SESS-103', 'High-Concurrency Ticketing Systems', 'Technical_Talk', '2026-12-10 14:00:00', '2026-12-10 15:30:00', 120);

INSERT INTO ATTENDEE (full_name, email, phone, organization, designation, city) VALUES
('Aarav Mehta', 'aarav@techcorp.in', '9876543210', 'TechCorp', 'Data Engineer', 'New Delhi'),
('Priya Sharma', 'priya@innovate.io', '9876543211', 'InnovateIO', 'Backend Lead', 'Bengaluru'),
('Kabir Nair', 'kabir@cloudops.in', '9876543212', 'CloudOps', 'SRE', 'Mumbai'),
('Diya Verma', 'diya@analytics.co', '9876543213', 'AnalyticsCo', 'ML Engineer', 'Pune'),
('Vikram Singh', 'vikram@startup.in', '9876543214', 'StartupHub', 'Founder', 'New Delhi'),
('Neha Gupta', 'neha@enterprise.in', '9876543215', 'EnterpriseSys', 'Architect', 'Noida');

INSERT INTO TICKET_TYPE (event_id, category_name, price_inr, allocated_seats, sold_seats) VALUES
(1, 'Early Bird Pass', 2500.00, 3, 3),
(1, 'VIP All-Access', 5000.00, 2, 1),
(2, 'Workshop Pass', 1500.00, 40, 2);

INSERT INTO REGISTRATION (reg_code, event_id, attendee_id, ticket_type_id, registration_status) VALUES
('REG-1-1-101', 1, 1, 1, 'Checked_In'),
('REG-1-2-102', 1, 2, 1, 'Confirmed'),
('REG-1-3-103', 1, 3, 1, 'Confirmed'),
('REG-1-4-104', 1, 4, 2, 'Confirmed');

INSERT INTO TICKET (ticket_number, registration_id, ticket_type_id, qr_code_hash) VALUES
('TKT-1-01', 1, 1, 'a1b2c3d4e5f6010199aabbccddeeff00112233445566778899aabbccddeeff01'),
('TKT-2-01', 2, 1, 'b2c3d4e5f601010299aabbccddeeff00112233445566778899aabbccddeeff02'),
('TKT-3-01', 3, 1, 'c3d4e5f60101020399aabbccddeeff00112233445566778899aabbccddeeff03'),
('TKT-4-01', 4, 2, 'd4e5f6010102030499aabbccddeeff00112233445566778899aabbccddeeff04');

INSERT INTO PAYMENT (transaction_ref, registration_id, amount_inr, payment_method, payment_status) VALUES
('TXN-1001', 1, 2500.00, 'UPI', 'Paid'),
('TXN-1002', 2, 2500.00, 'Credit_Card', 'Paid'),
('TXN-1003', 3, 2500.00, 'UPI', 'Paid'),
('TXN-1004', 4, 5000.00, 'Net_Banking', 'Paid');

INSERT INTO CHECK_IN (registration_id, session_id, checkin_method, certificate_code) VALUES
(1, 1, 'QR_Scan', 'CERT-AI26-0001');

INSERT INTO SPONSOR (event_id, sponsor_name, tier, contribution_inr, contact_person, sponsorship_status) VALUES
(1, 'BharatCloud Systems', 'Title', 300000.00, 'R. Malhotra', 'Received'),
(1, 'DataPulse Analytics', 'Gold', 150000.00, 'S. Kulkarni', 'Received');

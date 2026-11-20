-- ============================================================================
-- EVENT, CONFERENCE AND VENUE MANAGEMENT SYSTEM (MySQL 8.0+)
-- Team: Shreya Adhikari (TCA2573041)
-- ============================================================================

DROP DATABASE IF EXISTS event_ops_db;
CREATE DATABASE event_ops_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
USE event_ops_db;

-- ============================================================================
-- 1. CORE TABLES (13 Tables)
-- ============================================================================

CREATE TABLE VENUE (
    venue_id INT AUTO_INCREMENT PRIMARY KEY,
    venue_name VARCHAR(120) NOT NULL UNIQUE,
    city VARCHAR(80) NOT NULL,
    address VARCHAR(200) NOT NULL,
    total_capacity INT NOT NULL,
    contact_email VARCHAR(120) NOT NULL,
    rental_cost_inr DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT chk_venue_cap CHECK (total_capacity > 0)
) ENGINE=InnoDB;

CREATE TABLE ROOM (
    room_id INT AUTO_INCREMENT PRIMARY KEY,
    venue_id INT NOT NULL,
    room_code VARCHAR(20) NOT NULL UNIQUE,
    room_name VARCHAR(100) NOT NULL,
    room_type ENUM('Main_Auditorium', 'Conference_Hall', 'Workshop_Lab', 'Boardroom') NOT NULL,
    max_capacity INT NOT NULL,
    has_av_system BOOLEAN NOT NULL DEFAULT TRUE,
    room_status ENUM('Available', 'Maintenance', 'Reserved') NOT NULL DEFAULT 'Available',
    CONSTRAINT fk_room_venue FOREIGN KEY (venue_id)
        REFERENCES VENUE(venue_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_room_cap CHECK (max_capacity > 0)
) ENGINE=InnoDB;

CREATE TABLE EVENT (
    event_id INT AUTO_INCREMENT PRIMARY KEY,
    event_code VARCHAR(20) NOT NULL UNIQUE,
    event_name VARCHAR(140) NOT NULL,
    event_type ENUM('Conference', 'Workshop', 'Summit', 'Hackathon') NOT NULL,
    venue_id INT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    total_capacity INT NOT NULL,
    confirmed_count INT NOT NULL DEFAULT 0,
    waitlist_count INT NOT NULL DEFAULT 0,
    base_expense_inr DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    event_status ENUM('Upcoming', 'Ongoing', 'Completed', 'Cancelled') NOT NULL DEFAULT 'Upcoming',
    CONSTRAINT fk_event_venue FOREIGN KEY (venue_id)
        REFERENCES VENUE(venue_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_event_dates CHECK (end_date >= start_date),
    CONSTRAINT chk_event_cap CHECK (total_capacity > 0 AND confirmed_count <= total_capacity)
) ENGINE=InnoDB;

CREATE TABLE SPEAKER (
    speaker_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    organization VARCHAR(120) NOT NULL,
    expertise_area VARCHAR(100) NOT NULL,
    email VARCHAR(120) NOT NULL UNIQUE,
    honorarium_inr DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    speaker_status ENUM('Confirmed', 'Invited', 'Unavailable') NOT NULL DEFAULT 'Confirmed'
) ENGINE=InnoDB;

CREATE TABLE SESSION (
    session_id INT AUTO_INCREMENT PRIMARY KEY,
    event_id INT NOT NULL,
    room_id INT NOT NULL,
    speaker_id INT NOT NULL,
    session_code VARCHAR(24) NOT NULL UNIQUE,
    session_title VARCHAR(160) NOT NULL,
    session_type ENUM('Keynote', 'Technical_Talk', 'Workshop', 'Panel') NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    session_capacity INT NOT NULL,
    session_status ENUM('Scheduled', 'In_Progress', 'Completed', 'Cancelled') NOT NULL DEFAULT 'Scheduled',
    CONSTRAINT fk_sess_event FOREIGN KEY (event_id)
        REFERENCES EVENT(event_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_sess_room FOREIGN KEY (room_id)
        REFERENCES ROOM(room_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_sess_speaker FOREIGN KEY (speaker_id)
        REFERENCES SPEAKER(speaker_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT chk_sess_times CHECK (end_time > start_time)
) ENGINE=InnoDB;

CREATE TABLE ATTENDEE (
    attendee_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(120) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL,
    organization VARCHAR(120) NOT NULL,
    designation VARCHAR(80) NOT NULL,
    city VARCHAR(80) NOT NULL
) ENGINE=InnoDB;

CREATE TABLE TICKET_TYPE (
    ticket_type_id INT AUTO_INCREMENT PRIMARY KEY,
    event_id INT NOT NULL,
    category_name VARCHAR(60) NOT NULL,
    price_inr DECIMAL(10,2) NOT NULL,
    allocated_seats INT NOT NULL,
    sold_seats INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_event_ticket_cat UNIQUE (event_id, category_name),
    CONSTRAINT fk_tt_event FOREIGN KEY (event_id)
        REFERENCES EVENT(event_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_tt_seats CHECK (allocated_seats > 0 AND sold_seats <= allocated_seats)
) ENGINE=InnoDB;

CREATE TABLE REGISTRATION (
    registration_id INT AUTO_INCREMENT PRIMARY KEY,
    reg_code VARCHAR(24) NOT NULL UNIQUE,
    event_id INT NOT NULL,
    attendee_id INT NOT NULL,
    ticket_type_id INT NOT NULL,
    registration_status ENUM('Confirmed', 'Waitlisted', 'Cancelled', 'Checked_In') NOT NULL DEFAULT 'Confirmed',
    waitlist_position INT NULL,
    registered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_event_attendee UNIQUE (event_id, attendee_id),
    CONSTRAINT fk_reg_event FOREIGN KEY (event_id)
        REFERENCES EVENT(event_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_reg_attendee FOREIGN KEY (attendee_id)
        REFERENCES ATTENDEE(attendee_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_reg_ticket_type FOREIGN KEY (ticket_type_id)
        REFERENCES TICKET_TYPE(ticket_type_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE TICKET (
    ticket_id INT AUTO_INCREMENT PRIMARY KEY,
    ticket_number VARCHAR(30) NOT NULL UNIQUE,
    registration_id INT NOT NULL UNIQUE,
    ticket_type_id INT NOT NULL,
    qr_code_hash VARCHAR(64) NOT NULL UNIQUE,
    issue_status ENUM('Active', 'Used', 'Voided') NOT NULL DEFAULT 'Active',
    issued_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ticket_reg FOREIGN KEY (registration_id)
        REFERENCES REGISTRATION(registration_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_ticket_type FOREIGN KEY (ticket_type_id)
        REFERENCES TICKET_TYPE(ticket_type_id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE PAYMENT (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    transaction_ref VARCHAR(36) NOT NULL UNIQUE,
    registration_id INT NOT NULL,
    amount_inr DECIMAL(10,2) NOT NULL,
    payment_method ENUM('UPI', 'Credit_Card', 'Debit_Card', 'Net_Banking', 'Corporate_Invoice') NOT NULL,
    payment_status ENUM('Paid', 'Pending', 'Failed', 'Refunded') NOT NULL DEFAULT 'Paid',
    paid_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pay_reg FOREIGN KEY (registration_id)
        REFERENCES REGISTRATION(registration_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT chk_pay_amount CHECK (amount_inr >= 0.00)
) ENGINE=InnoDB;

CREATE TABLE REFUND (
    refund_id INT AUTO_INCREMENT PRIMARY KEY,
    refund_ref VARCHAR(36) NOT NULL UNIQUE,
    payment_id INT NOT NULL,
    registration_id INT NOT NULL,
    refund_amount_inr DECIMAL(10,2) NOT NULL,
    refund_reason VARCHAR(200) NOT NULL,
    refund_status ENUM('Processed', 'Pending') NOT NULL DEFAULT 'Processed',
    processed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ref_payment FOREIGN KEY (payment_id)
        REFERENCES PAYMENT(payment_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_ref_reg FOREIGN KEY (registration_id)
        REFERENCES REGISTRATION(registration_id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE CHECK_IN (
    checkin_id INT AUTO_INCREMENT PRIMARY KEY,
    registration_id INT NOT NULL,
    session_id INT NOT NULL,
    checkin_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    checkin_method ENUM('QR_Scan', 'Desk_Manual') NOT NULL DEFAULT 'QR_Scan',
    certificate_code VARCHAR(32) NOT NULL UNIQUE,
    certificate_issued BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_reg_session_checkin UNIQUE (registration_id, session_id),
    CONSTRAINT fk_chk_reg FOREIGN KEY (registration_id)
        REFERENCES REGISTRATION(registration_id) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_chk_sess FOREIGN KEY (session_id)
        REFERENCES SESSION(session_id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE SPONSOR (
    sponsor_id INT AUTO_INCREMENT PRIMARY KEY,
    event_id INT NOT NULL,
    sponsor_name VARCHAR(120) NOT NULL,
    tier ENUM('Title', 'Platinum', 'Gold', 'Silver') NOT NULL,
    contribution_inr DECIMAL(12,2) NOT NULL,
    contact_person VARCHAR(100) NOT NULL,
    sponsorship_status ENUM('Confirmed', 'Pledged', 'Received') NOT NULL DEFAULT 'Received',
    CONSTRAINT fk_spons_event FOREIGN KEY (event_id)
        REFERENCES EVENT(event_id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ============================================================================
-- 2. INDEXES
-- ============================================================================

CREATE INDEX idx_sess_room_window ON SESSION (room_id, start_time, end_time, session_status);
CREATE INDEX idx_sess_speaker_window ON SESSION (speaker_id, start_time, end_time, session_status);
CREATE INDEX idx_reg_event_status ON REGISTRATION (event_id, registration_status, waitlist_position);

-- ============================================================================
-- 3. FUNCTIONS & TRIGGERS (Room & Speaker Conflict Prevention)
-- ============================================================================

DELIMITER $$

CREATE FUNCTION fn_check_room_overlap(
    p_room_id INT,
    p_start DATETIME,
    p_end DATETIME,
    p_exclude_session_id INT
)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_cnt INT DEFAULT 0;
    SELECT COUNT(*) INTO v_cnt
    FROM SESSION
    WHERE room_id = p_room_id
      AND session_status <> 'Cancelled'
      AND (p_exclude_session_id IS NULL OR session_id <> p_exclude_session_id)
      AND p_start < DATE_ADD(end_time, INTERVAL 15 MINUTE)
      AND p_end > DATE_SUB(start_time, INTERVAL 15 MINUTE);
    RETURN v_cnt;
END$$

CREATE FUNCTION fn_check_speaker_overlap(
    p_speaker_id INT,
    p_start DATETIME,
    p_end DATETIME,
    p_exclude_session_id INT
)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_cnt INT DEFAULT 0;
    SELECT COUNT(*) INTO v_cnt
    FROM SESSION
    WHERE speaker_id = p_speaker_id
      AND session_status <> 'Cancelled'
      AND (p_exclude_session_id IS NULL OR session_id <> p_exclude_session_id)
      AND p_start < end_time
      AND p_end > start_time;
    RETURN v_cnt;
END$$

CREATE TRIGGER trg_before_session_insert
BEFORE INSERT ON SESSION
FOR EACH ROW
BEGIN
    DECLARE v_room_status VARCHAR(20);
    DECLARE v_room_cap INT;

    SELECT room_status, max_capacity INTO v_room_status, v_room_cap
    FROM ROOM WHERE room_id = NEW.room_id;

    IF v_room_status = 'Maintenance' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ROOM CONFLICT: Selected room is under maintenance.';
    END IF;

    IF NEW.session_capacity > v_room_cap THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'CAPACITY CONFLICT: Session capacity exceeds room maximum capacity.';
    END IF;

    IF fn_check_room_overlap(NEW.room_id, NEW.start_time, NEW.end_time, NULL) > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ROOM CONFLICT: Room is already booked in this window (15-min turnover buffer enforced).';
    END IF;

    IF fn_check_speaker_overlap(NEW.speaker_id, NEW.start_time, NEW.end_time, NULL) > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SPEAKER CONFLICT: Speaker is already assigned to an overlapping session.';
    END IF;
END$$

-- ============================================================================
-- 4. STORED PROCEDURES (Advanced Challenge: Concurrency-Safe Seat Booking)
-- ============================================================================

CREATE PROCEDURE sp_register_attendee_atomic(
    IN p_event_id INT,
    IN p_attendee_id INT,
    IN p_ticket_type_id INT,
    IN p_payment_method VARCHAR(30),
    OUT p_outcome VARCHAR(60)
)
BEGIN
    DECLARE v_ev_cap INT;
    DECLARE v_ev_conf INT;
    DECLARE v_ev_wait INT;
    DECLARE v_tt_alloc INT;
    DECLARE v_tt_sold INT;
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_dup_count INT DEFAULT 0;
    DECLARE v_reg_id INT;
    DECLARE v_reg_code VARCHAR(24);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Prevent duplicate registration for the same event
    SELECT COUNT(*) INTO v_dup_count
    FROM REGISTRATION
    WHERE event_id = p_event_id AND attendee_id = p_attendee_id AND registration_status <> 'Cancelled';

    IF v_dup_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'DUPLICATE BLOCKED: Attendee is already registered or waitlisted for this event.';
    END IF;

    -- Lock EVENT and TICKET_TYPE rows (Pessimistic Locking for final seats)
    SELECT total_capacity, confirmed_count, waitlist_count
    INTO v_ev_cap, v_ev_conf, v_ev_wait
    FROM EVENT WHERE event_id = p_event_id FOR UPDATE;

    SELECT allocated_seats, sold_seats, price_inr
    INTO v_tt_alloc, v_tt_sold, v_price
    FROM TICKET_TYPE WHERE ticket_type_id = p_ticket_type_id AND event_id = p_event_id FOR UPDATE;

    SET v_reg_code = CONCAT('REG-', p_event_id, '-', p_attendee_id, '-', FLOOR(100 + RAND() * 899));

    IF v_ev_conf < v_ev_cap AND v_tt_sold < v_tt_alloc THEN
        INSERT INTO REGISTRATION (reg_code, event_id, attendee_id, ticket_type_id, registration_status, waitlist_position)
        VALUES (v_reg_code, p_event_id, p_attendee_id, p_ticket_type_id, 'Confirmed', NULL);
        SET v_reg_id = LAST_INSERT_ID();

        UPDATE EVENT SET confirmed_count = confirmed_count + 1 WHERE event_id = p_event_id;
        UPDATE TICKET_TYPE SET sold_seats = sold_seats + 1 WHERE ticket_type_id = p_ticket_type_id;

        INSERT INTO TICKET (ticket_number, registration_id, ticket_type_id, qr_code_hash)
        VALUES (CONCAT('TKT-', v_reg_id, '-', LPAD(p_event_id, 2, '0')), v_reg_id, p_ticket_type_id, SHA2(CONCAT(v_reg_code, NOW()), 256));

        INSERT INTO PAYMENT (transaction_ref, registration_id, amount_inr, payment_method, payment_status)
        VALUES (CONCAT('TXN-', v_reg_id, '-', UNIX_TIMESTAMP()), v_reg_id, v_price, p_payment_method, 'Paid');

        SET p_outcome = CONCAT('CONFIRMED (', v_reg_code, ')');
    ELSE
        UPDATE EVENT SET waitlist_count = waitlist_count + 1 WHERE event_id = p_event_id;
        INSERT INTO REGISTRATION (reg_code, event_id, attendee_id, ticket_type_id, registration_status, waitlist_position)
        VALUES (v_reg_code, p_event_id, p_attendee_id, p_ticket_type_id, 'Waitlisted', v_ev_wait + 1);

        SET p_outcome = CONCAT('WAITLISTED #', v_ev_wait + 1, ' (', v_reg_code, ')');
    END IF;

    COMMIT;
END$$

CREATE PROCEDURE sp_cancel_and_promote_waitlist(
    IN p_registration_id INT,
    IN p_reason VARCHAR(200)
)
BEGIN
    DECLARE v_event_id INT;
    DECLARE v_tt_id INT;
    DECLARE v_status VARCHAR(20);
    DECLARE v_pay_id INT;
    DECLARE v_amount DECIMAL(10,2);
    DECLARE v_next_reg_id INT DEFAULT NULL;
    DECLARE v_next_tt_id INT DEFAULT NULL;
    DECLARE v_next_price DECIMAL(10,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT event_id, ticket_type_id, registration_status
    INTO v_event_id, v_tt_id, v_status
    FROM REGISTRATION WHERE registration_id = p_registration_id FOR UPDATE;

    IF v_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Registration is already cancelled.';
    END IF;

    UPDATE REGISTRATION SET registration_status = 'Cancelled' WHERE registration_id = p_registration_id;
    UPDATE TICKET SET issue_status = 'Voided' WHERE registration_id = p_registration_id;

    IF v_status IN ('Confirmed', 'Checked_In') THEN
        SELECT payment_id, amount_inr INTO v_pay_id, v_amount
        FROM PAYMENT WHERE registration_id = p_registration_id LIMIT 1;

        IF v_pay_id IS NOT NULL THEN
            UPDATE PAYMENT SET payment_status = 'Refunded' WHERE payment_id = v_pay_id;
            INSERT INTO REFUND (refund_ref, payment_id, registration_id, refund_amount_inr, refund_reason)
            VALUES (CONCAT('RFD-', p_registration_id, '-', UNIX_TIMESTAMP()), v_pay_id, p_registration_id, v_amount, p_reason);
        END IF;

        UPDATE EVENT SET confirmed_count = GREATEST(confirmed_count - 1, 0) WHERE event_id = v_event_id;
        UPDATE TICKET_TYPE SET sold_seats = GREATEST(sold_seats - 1, 0) WHERE ticket_type_id = v_tt_id;

        -- Promote earliest waitlisted attendee for this event
        SELECT registration_id, ticket_type_id INTO v_next_reg_id, v_next_tt_id
        FROM REGISTRATION
        WHERE event_id = v_event_id AND registration_status = 'Waitlisted'
        ORDER BY waitlist_position ASC, registered_at ASC
        LIMIT 1 FOR UPDATE;

        IF v_next_reg_id IS NOT NULL THEN
            SELECT price_inr INTO v_next_price FROM TICKET_TYPE WHERE ticket_type_id = v_next_tt_id;
            UPDATE REGISTRATION SET registration_status = 'Confirmed', waitlist_position = NULL WHERE registration_id = v_next_reg_id;
            UPDATE EVENT SET confirmed_count = confirmed_count + 1, waitlist_count = GREATEST(waitlist_count - 1, 0) WHERE event_id = v_event_id;
            UPDATE TICKET_TYPE SET sold_seats = sold_seats + 1 WHERE ticket_type_id = v_next_tt_id;

            INSERT INTO TICKET (ticket_number, registration_id, ticket_type_id, qr_code_hash)
            VALUES (CONCAT('TKT-', v_next_reg_id, '-PROMO'), v_next_reg_id, v_next_tt_id, SHA2(CONCAT(v_next_reg_id, NOW()), 256));

            INSERT INTO PAYMENT (transaction_ref, registration_id, amount_inr, payment_method, payment_status)
            VALUES (CONCAT('TXN-PROMO-', v_next_reg_id), v_next_reg_id, v_next_price, 'UPI', 'Paid');
        END IF;
    END IF;

    COMMIT;
END$$

DELIMITER ;

-- ============================================================================
-- 5. ANALYTICAL VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW vw_event_financial_and_capacity AS
SELECT
    e.event_id,
    e.event_code,
    e.event_name,
    e.event_type,
    v.venue_name,
    v.city,
    e.start_date,
    e.total_capacity,
    e.confirmed_count,
    (e.total_capacity - e.confirmed_count) AS remaining_seats,
    e.waitlist_count,
    COALESCE((SELECT SUM(p.amount_inr) FROM PAYMENT p JOIN REGISTRATION r ON p.registration_id = r.registration_id WHERE r.event_id = e.event_id AND p.payment_status = 'Paid'), 0) AS ticket_revenue_inr,
    COALESCE((SELECT SUM(s.contribution_inr) FROM SPONSOR s WHERE s.event_id = e.event_id), 0) AS sponsor_revenue_inr,
    (e.base_expense_inr + v.rental_cost_inr) AS total_expense_inr
FROM EVENT e
JOIN VENUE v ON e.venue_id = v.venue_id;

CREATE OR REPLACE VIEW vw_session_schedule_board AS
SELECT
    s.session_id,
    s.session_code,
    e.event_name,
    s.session_title,
    s.session_type,
    r.room_code,
    r.room_name,
    sp.full_name AS speaker_name,
    sp.organization,
    s.start_time,
    s.end_time,
    s.session_capacity,
    s.session_status
FROM SESSION s
JOIN EVENT e ON s.event_id = e.event_id
JOIN ROOM r ON s.room_id = r.room_id
JOIN SPEAKER sp ON s.speaker_id = sp.speaker_id;

CREATE OR REPLACE VIEW vw_attendance_certificates AS
SELECT
    c.checkin_id,
    c.certificate_code,
    a.full_name AS attendee_name,
    a.organization,
    e.event_name,
    s.session_title,
    c.checkin_time,
    c.checkin_method
FROM CHECK_IN c
JOIN REGISTRATION r ON c.registration_id = r.registration_id
JOIN ATTENDEE a ON r.attendee_id = a.attendee_id
JOIN EVENT e ON r.event_id = e.event_id
JOIN SESSION s ON c.session_id = s.session_id;

-- ============================================================================
-- 6. SAMPLE SEED DATA
-- ============================================================================

INSERT INTO VENUE (venue_name, city, address, total_capacity, contact_email, rental_cost_inr) VALUES
('Bharat Mandapam Convention Centre', 'New Delhi', 'Pragati Maidan, New Delhi', 1500, 'events@bharatmandapam.in', 250000.00),
('Jio World Convention Centre', 'Mumbai', 'BKC, Bandra East, Mumbai', 1200, 'bookings@jioworld.in', 220000.00);

INSERT INTO ROOM (venue_id, room_code, room_name, room_type, max_capacity, has_av_system, room_status) VALUES
(1, 'BM-AUD1', 'Plenary Hall A', 'Main_Auditorium', 300, TRUE, 'Available'),
(1, 'BM-WS1', 'AI Workshop Lab 1', 'Workshop_Lab', 60, TRUE, 'Available'),
(1, 'BM-CONF2', 'Cloud Summit Hall', 'Conference_Hall', 150, TRUE, 'Available'),
(2, 'JW-AUD1', 'Grand Ballroom', 'Main_Auditorium', 250, TRUE, 'Available');

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
('TKT-1-01', 1, 1, SHA2('REG-1-1-101', 256)),
('TKT-2-01', 2, 1, SHA2('REG-1-2-102', 256)),
('TKT-3-01', 3, 1, SHA2('REG-1-3-103', 256)),
('TKT-4-01', 4, 2, SHA2('REG-1-4-104', 256));

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

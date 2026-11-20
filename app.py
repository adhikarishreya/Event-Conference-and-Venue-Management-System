"""
Event, Conference and Venue Management System - Streamlit Web Dashboard
Team: Shreya Adhikari (TCA2573041)
"""

import os
import streamlit as st
import pandas as pd
import plotly.express as px
import mysql.connector
from mysql.connector import Error

st.set_page_config(
    page_title="EventOps | Conference & Venue Management DBMS",
    page_icon="🎟️",
    layout="wide",
    initial_sidebar_state="expanded",
)

def get_db_connection():
    return mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", "rootpassword123"),
        database=os.getenv("DB_NAME", "event_ops_db"),
        autocommit=False,
    )

def query_df(sql: str, params=None) -> pd.DataFrame:
    conn = get_db_connection()
    try:
        return pd.read_sql(sql, conn, params=params)
    finally:
        conn.close()

def execute_dml(sql: str, params: tuple):
    conn = get_db_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(sql, params)
        conn.commit()
    except Exception as exc:
        conn.rollback()
        raise exc
    finally:
        cursor.close()
        conn.close()

st.sidebar.markdown("## 🎟️ EventOps DBMS")
st.sidebar.caption("**Team:**\n• Shreya Adhikari (`TCA2573041`)")
st.sidebar.markdown("---")

page = st.sidebar.radio(
    "Operations Module",
    [
        "📊 Event Board, Sales & P&L",
        "⚡ Concurrent Seat & Waitlist Lab",
        "🏛️ Sessions, Rooms & Conflict Guard",
        "💳 Payments, Cancellations & Refunds",
        "🎫 Check-In & Certificates",
        "🤝 Sponsors & Ticket Categories",
    ],
)

st.title("🎟️ Event, Conference & Venue Management System")
st.caption("Team: **Shreya Adhikari (TCA2573041)** | MySQL 8.0 + Concurrency Locking + Room Conflict Triggers")

if page == "📊 Event Board, Sales & P&L":
    try:
        ev_df = query_df("SELECT * FROM vw_event_financial_and_capacity")
        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Active Events", len(ev_df))
        c2.metric("Confirmed Seats", int(ev_df["confirmed_count"].sum()), f"Waitlisted: {int(ev_df['waitlist_count'].sum())}")
        total_rev = ev_df["ticket_revenue_inr"].sum() + ev_df["sponsor_revenue_inr"].sum()
        c3.metric("Total Revenue (INR)", f"₹{total_rev:,.0f}")
        c4.metric("Total Expenses (INR)", f"₹{ev_df['total_expense_inr'].sum():,.0f}")

        col1, col2 = st.columns(2)
        with col1:
            st.subheader("Event Capacity vs. Confirmed & Waitlisted")
            fig_cap = px.bar(ev_df, x="event_code", y=["confirmed_count", "remaining_seats", "waitlist_count"], barmode="group")
            st.plotly_chart(fig_cap, use_container_width=True)
        with col2:
            st.subheader("Revenue Breakdown (Tickets vs. Sponsors vs. Expenses)")
            fig_fin = px.bar(ev_df, x="event_code", y=["ticket_revenue_inr", "sponsor_revenue_inr", "total_expense_inr"], barmode="group")
            st.plotly_chart(fig_fin, use_container_width=True)

        st.dataframe(ev_df, use_container_width=True, hide_index=True)
    except Error as err:
        st.error(f"MySQL Error: {err}")

elif page == "⚡ Concurrent Seat & Waitlist Lab":
    st.subheader("⚡ Advanced Challenge: Final-Seat Locking & Duplicate Guard")
    st.markdown("Calls `sp_register_attendee_atomic` using `FOR UPDATE` row locks. Note `CONF-AI-26` has **4/5 seats filled**—registering a 5th attendee confirms them, and a 6th automatically enters the **Waitlist**.")
    ev_df = query_df("SELECT event_id, event_code, event_name, confirmed_count, total_capacity, waitlist_count FROM EVENT")
    att_df = query_df("SELECT attendee_id, full_name, email FROM ATTENDEE")
    tt_df = query_df("SELECT ticket_type_id, event_id, category_name, price_inr, sold_seats, allocated_seats FROM TICKET_TYPE")
    st.dataframe(ev_df, use_container_width=True, hide_index=True)

    with st.form("reg_form"):
        c1, c2, c3, c4 = st.columns(4)
        ev_id = c1.selectbox("Event", ev_df["event_id"].tolist(), format_func=lambda x: ev_df.loc[ev_df["event_id"] == x, "event_code"].values[0])
        att_id = c2.selectbox("Attendee", att_df["attendee_id"].tolist(), format_func=lambda x: att_df.loc[att_df["attendee_id"] == x, "full_name"].values[0])
        tt_id = c3.selectbox("Ticket Category", tt_df["ticket_type_id"].tolist(), format_func=lambda x: f"{tt_df.loc[tt_df['ticket_type_id']==x, 'category_name'].values[0]} (₹{tt_df.loc[tt_df['ticket_type_id']==x, 'price_inr'].values[0]})")
        pmethod = c4.selectbox("Payment Method", ["UPI", "Credit_Card", "Debit_Card", "Net_Banking"])

        if st.form_submit_button("🔒 Register Attendee (ACID Locked)"):
            conn = get_db_connection()
            cur = conn.cursor()
            try:
                res = cur.callproc("sp_register_attendee_atomic", (int(ev_id), int(att_id), int(tt_id), pmethod, ""))
                conn.commit()
                st.success(f"Result: {res[4]}")
                st.rerun()
            except Exception as exc:
                conn.rollback()
                st.error(f"Blocked / Rolled Back: {exc}")
            finally:
                cur.close()
                conn.close()

elif page == "🏛️ Sessions, Rooms & Conflict Guard":
    st.subheader("🏛️ Conference Sessions (`vw_session_schedule_board`)")
    sess_df = query_df("SELECT * FROM vw_session_schedule_board ORDER BY start_time")
    st.dataframe(sess_df, use_container_width=True, hide_index=True)

    st.subheader("🛡️ Schedule New Session (Room & Speaker Overlap Trigger)")
    rooms = query_df("SELECT room_id, room_code, room_name, max_capacity FROM ROOM")
    speakers = query_df("SELECT speaker_id, full_name FROM SPEAKER")
    events = query_df("SELECT event_id, event_code FROM EVENT")

    with st.form("sess_form"):
        c1, c2, c3 = st.columns(3)
        ev_id = c1.selectbox("Event", events["event_id"].tolist(), format_func=lambda x: events.loc[events["event_id"] == x, "event_code"].values[0])
        rm_id = c2.selectbox("Room", rooms["room_id"].tolist(), format_func=lambda x: f"{rooms.loc[rooms['room_id']==x, 'room_code'].values[0]} (Cap {rooms.loc[rooms['room_id']==x, 'max_capacity'].values[0]})")
        sp_id = c3.selectbox("Speaker", speakers["speaker_id"].tolist(), format_func=lambda x: speakers.loc[speakers["speaker_id"] == x, "full_name"].values[0])
        c4, c5, c6 = st.columns(3)
        s_code = c4.text_input("Session Code", "SESS-104")
        s_title = c5.text_input("Session Title", "Database Concurrency Deep Dive")
        s_cap = c6.number_input("Capacity", min_value=10, value=50)
        start_t = st.text_input("Start Time (YYYY-MM-DD HH:MM:SS)", "2026-12-10 09:45:00")
        end_t = st.text_input("End Time (YYYY-MM-DD HH:MM:SS)", "2026-12-10 10:45:00")

        if st.form_submit_button("Assign Room & Speaker"):
            try:
                execute_dml(
                    "INSERT INTO SESSION (event_id, room_id, speaker_id, session_code, session_title, session_type, start_time, end_time, session_capacity) VALUES (%s,%s,%s,%s,%s,'Technical_Talk',%s,%s,%s)",
                    (int(ev_id), int(rm_id), int(sp_id), s_code, s_title, start_t, end_t, int(s_cap)),
                )
                st.success("Session scheduled!")
                st.rerun()
            except Exception as exc:
                st.error(f"Trigger Blocked Conflict: {exc}")

elif page == "💳 Payments, Cancellations & Refunds":
    st.subheader("💳 Cancel Registration & Auto-Promote Waitlist")
    reg_df = query_df("""
        SELECT r.registration_id, r.reg_code, a.full_name, e.event_code, r.registration_status, r.waitlist_position
        FROM REGISTRATION r
        JOIN ATTENDEE a ON r.attendee_id = a.attendee_id
        JOIN EVENT e ON r.event_id = e.event_id
        ORDER BY r.registration_id DESC
    """)
    st.dataframe(reg_df, use_container_width=True, hide_index=True)

    active_regs = reg_df[reg_df["registration_status"].isin(["Confirmed", "Waitlisted"])]
    if not active_regs.empty:
        with st.form("cancel_form"):
            r_id = st.selectbox("Select Registration to Cancel", active_regs["registration_id"].tolist(), format_func=lambda x: f"{active_regs.loc[active_regs['registration_id']==x, 'reg_code'].values[0]} - {active_regs.loc[active_regs['registration_id']==x, 'full_name'].values[0]}")
            reason = st.text_input("Cancellation Reason", "Attendee schedule conflict")
            if st.form_submit_button("Cancel & Process Refund / Promote Waitlist"):
                conn = get_db_connection()
                cur = conn.cursor()
                try:
                    cur.callproc("sp_cancel_and_promote_waitlist", (int(r_id), reason))
                    conn.commit()
                    st.success("Cancelled, refunded, and promoted next waitlisted attendee (if any)!")
                    st.rerun()
                except Exception as exc:
                    conn.rollback()
                    st.error(f"Error: {exc}")
                finally:
                    cur.close()
                    conn.close()

    st.subheader("Refund Ledger (`REFUND`)")
    st.dataframe(query_df("SELECT * FROM REFUND ORDER BY refund_id DESC"), use_container_width=True, hide_index=True)

elif page == "🎫 Check-In & Certificates":
    st.subheader("🎫 Attendee Check-In & Attendance Certificates")
    certs = query_df("SELECT * FROM vw_attendance_certificates ORDER BY checkin_time DESC")
    st.dataframe(certs, use_container_width=True, hide_index=True)

elif page == "🤝 Sponsors & Ticket Categories":
    st.subheader("🤝 Event Sponsors (`SPONSOR`)")
    st.dataframe(query_df("SELECT * FROM SPONSOR"), use_container_width=True, hide_index=True)
    st.subheader("🎟️ Ticket Categories (`TICKET_TYPE`)")
    st.dataframe(query_df("SELECT * FROM TICKET_TYPE"), use_container_width=True, hide_index=True)

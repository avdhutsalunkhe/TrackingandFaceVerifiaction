import time as time_lib
from datetime import datetime, time, timezone
import pytz
import cv2
import numpy as np
from typing import Dict, Any, List, Optional

SERVER_TIMEZONE_NAME = "Asia/Kolkata"

class TimeService:
    @staticmethod
    def get_server_timezone():
        return pytz.timezone(SERVER_TIMEZONE_NAME)

    @classmethod
    def get_current_server_time(cls) -> Dict[str, Any]:
        """
        Authoritative server time representation.
        The server clock is the single source of truth.
        """
        tz = cls.get_server_timezone()
        now_utc = datetime.now(timezone.utc)
        local_dt = datetime.now(tz)

        formatted_date = local_dt.strftime("%d %b %Y")
        formatted_time = local_dt.strftime("%I:%M:%S %p")

        return {
            "server_timestamp": now_utc.strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            "server_date": local_dt.strftime("%Y-%m-%d"),
            "server_time": local_dt.strftime("%H:%M:%S"),
            "formatted_date": formatted_date,
            "formatted_time": formatted_time,
            "timezone": SERVER_TIMEZONE_NAME,
            "epoch_ms": int(time_lib.time() * 1000)
        }

    @classmethod
    def format_datetime_ist(cls, dt: Optional[datetime]) -> Dict[str, Optional[str]]:
        """
        Converts a datetime object (naive UTC or tz-aware) into Asia/Kolkata timezone.
        Returns dict with: iso_timestamp, formatted_date, formatted_time
        e.g. ("2026-10-02T09:23:19+05:30", "02 Oct 2026", "09:23:19 AM")
        """
        if not dt:
            return {"timestamp": None, "formatted_date": None, "formatted_time": None}
        tz = cls.get_server_timezone()
        if dt.tzinfo is None:
            local_dt = pytz.utc.localize(dt).astimezone(tz)
        else:
            local_dt = dt.astimezone(tz)

        return {
            "timestamp": local_dt.isoformat(),
            "formatted_date": local_dt.strftime("%d %b %Y"),
            "formatted_time": local_dt.strftime("%I:%M:%S %p")
        }


    @classmethod
    def _get_fallback_default_rules(cls) -> List[Dict[str, Any]]:
        """No hardcoded fallback rules. Shift rules must come from database."""
        return []

    @classmethod
    def resolve_shift_punch_periods_list(cls, shift: Optional[Any]) -> List[Dict[str, Any]]:
        """Extracts active punch periods from shift object."""
        if not shift:
            return []

        raw_periods = getattr(shift, "punch_periods", None) or getattr(shift, "rules", None)
        if raw_periods:
            active_periods = [p for p in raw_periods if getattr(p, "is_active", True)]
            if active_periods:
                # Sort by priority or punch_no or start_time
                sorted_periods = sorted(
                    active_periods,
                    key=lambda x: (getattr(x, "priority", 1), getattr(x, "punch_no", getattr(x, "verification_no", 1)), x.start_time)
                )
                result = []
                for idx, p in enumerate(sorted_periods, start=1):
                    p_no = getattr(p, "punch_no", getattr(p, "verification_no", idx)) or idx
                    p_name = getattr(p, "period_name", None) or getattr(p, "rule_name", f"Punch #{p_no}")
                    st_str = p.start_time.strftime("%H:%M:%S")
                    et_str = p.end_time.strftime("%H:%M:%S")
                    st_fmt = p.start_time.strftime("%I:%M %p")
                    et_fmt = p.end_time.strftime("%I:%M %p")
                    result.append({
                        "id": p.id,
                        "punch_period_id": p.id,
                        "punch_no": p_no,
                        "verification_no": p_no,
                        "period_name": p_name,
                        "rule_name": p_name,
                        "rule_code": getattr(p, "rule_code", f"PUNCH_{p_no}"),
                        "start_time": p.start_time,
                        "end_time": p.end_time,
                        "start": st_str,
                        "end": et_str,
                        "label": f"{st_fmt} – {et_fmt}",
                        "show_in_user_schedule": getattr(p, "show_in_user_schedule", True),
                        "require_face_verification": getattr(p, "require_face_verification", True),
                        "is_active": getattr(p, "is_active", True),
                        "result_classification": "PRESENT"
                    })
                return result

        return []

    @classmethod
    def resolve_shift_rules_list(cls, shift: Optional[Any]) -> List[Dict[str, Any]]:
        return cls.resolve_shift_punch_periods_list(shift)

    @classmethod
    def get_active_verification_window(cls, current_time: time, shift: Optional[Any] = None) -> Optional[Dict[str, Any]]:
        """
        Determines which active rule/punch period is currently open using half-open intervals:
        start_time <= current_time < end_time
        """
        rules = cls.resolve_shift_punch_periods_list(shift)
        for win in rules:
            if win["is_active"] and win["start_time"] <= current_time < win["end_time"]:
                return win
        return None

    @classmethod
    def get_next_verification_window(cls, current_time: time, shift: Optional[Any] = None) -> Optional[Dict[str, Any]]:
        """
        Finds the earliest upcoming user-visible punch period for today:
        current_time < start_time
        """
        rules = cls.resolve_shift_punch_periods_list(shift)
        for win in rules:
            if win["is_active"] and win["show_in_user_schedule"] and current_time < win["start_time"]:
                return win
        return None

    @classmethod
    def get_window_by_number(cls, verification_no: int, shift: Optional[Any] = None) -> Optional[Dict[str, Any]]:
        rules = cls.resolve_shift_punch_periods_list(shift)
        for win in rules:
            if win["punch_no"] == verification_no or win["verification_no"] == verification_no:
                return win
    @classmethod
    def get_punch_period_by_id(cls, period_id: int, shift: Optional[Any] = None) -> Optional[Dict[str, Any]]:
        rules = cls.resolve_shift_punch_periods_list(shift)
        for win in rules:
            if win["id"] == period_id or win.get("punch_period_id") == period_id:
                return win
        return None

    @classmethod
    def get_all_windows_status(
        cls,
        attendances: List[Any],
        current_time: time,
        shift: Optional[Any] = None
    ) -> Dict[str, Any]:
        """
        Dynamically calculates status for all user-visible shift punch periods using half-open intervals:
        - UPCOMING: current_time < start_time
        - AVAILABLE: start_time <= current_time < end_time AND not verified
        - COMPLETED: successful verification already exists
        - MISSED: current_time >= end_time AND not verified
        """
        if not shift:
            return {
                "has_active_shift": False,
                "current_verification": None,
                "verification_status": "NO_ACTIVE_SHIFT",
                "verification_rules": [],
                "verification_windows": [],
                "punch_periods": [],
                "next_verification": None,
                "attendance_action": {
                    "punch_allowed": False,
                    "active_punch_period_id": None,
                    "active_punch_period_name": None,
                    "reason": "NO_ACTIVE_SHIFT"
                }
            }

        all_rules = cls.resolve_shift_punch_periods_list(shift)
        user_visible_rules = [r for r in all_rules if r["show_in_user_schedule"] and r["is_active"]]

        # Build attendance lookup map by punch_period_id or verification_rule_id or verification_no
        completed_by_period_id = {}
        completed_by_rule_id = {}
        completed_by_v_no = {}
        for att in attendances:
            p_id = getattr(att, "punch_period_id", None)
            if p_id is not None:
                completed_by_period_id[p_id] = att
            r_id = getattr(att, "verification_rule_id", None)
            if r_id is not None:
                completed_by_rule_id[r_id] = att
            v_no = getattr(att, "verification_no", None)
            if v_no is not None:
                completed_by_v_no[v_no] = att

        windows_summary = []
        active_window = None
        next_window = None

        for win in user_visible_rules:
            p_id = win["id"]
            p_no = win["punch_no"]

            matched_att = (
                completed_by_period_id.get(p_id)
                or completed_by_rule_id.get(p_id)
                or completed_by_v_no.get(p_no)
            )

            if matched_att:
                status = "COMPLETED"
                punch_time_str = matched_att.timestamp.strftime("%I:%M:%S %p") if matched_att.timestamp else None
            else:
                punch_time_str = None
                if current_time < win["start_time"]:
                    status = "UPCOMING"
                    if next_window is None:
                        next_window = win
                elif win["start_time"] <= current_time < win["end_time"]:
                    status = "AVAILABLE"
                    if active_window is None:
                        active_window = win
                else:
                    status = "MISSED"

            period_dict = {
                "id": p_id,
                "punch_period_id": p_id,
                "punch_no": p_no,
                "verification_no": p_no,
                "name": win["period_name"],
                "period_name": win["period_name"],
                "rule_name": win["period_name"],
                "rule_code": win["rule_code"],
                "start_time": win["start"],
                "end_time": win["end"],
                "start": win["start"],
                "end": win["end"],
                "label": win["label"],
                "status": status,
                "punch_time": punch_time_str,
                "verified_at": punch_time_str,
                "show_in_user_schedule": True,
                "require_face_verification": win["require_face_verification"]
            }
            windows_summary.append(period_dict)

        current_v_no = active_window["punch_no"] if active_window else None
        if active_window:
            verif_status = "AVAILABLE"
        elif next_window:
            verif_status = "UPCOMING"
        elif len(windows_summary) > 0 and all(w["status"] == "COMPLETED" for w in windows_summary):
            verif_status = "COMPLETED"
        else:
            verif_status = "CLOSED"

        next_win_summary = None
        if next_window:
            next_win_summary = {
                "id": next_window["id"],
                "punch_period_id": next_window["id"],
                "punch_no": next_window["punch_no"],
                "verification_no": next_window["punch_no"],
                "name": next_window["period_name"],
                "period_name": next_window["period_name"],
                "rule_name": next_window["period_name"],
                "start": next_window["start"],
                "end": next_window["end"],
                "label": next_window["label"]
            }

        punch_allowed = (active_window is not None)
        action_reason = None
        if not punch_allowed:
            if verif_status == "COMPLETED":
                action_reason = "ALL_PUNCHES_COMPLETED"
            elif next_window:
                action_reason = f"NEXT_WINDOW_AT_{next_window['start']}"
            else:
                action_reason = "NO_OPEN_PUNCH_WINDOW"

        attendance_action = {
            "punch_allowed": punch_allowed,
            "active_punch_period_id": active_window["id"] if active_window else None,
            "active_punch_period_name": active_window["period_name"] if active_window else None,
            "reason": action_reason
        }

        return {
            "has_active_shift": True,
            "current_verification": current_v_no,
            "verification_status": verif_status,
            "verification_rules": windows_summary,
            "verification_windows": windows_summary,
            "punch_periods": windows_summary,
            "next_verification": next_win_summary,
            "attendance_action": attendance_action
        }

    @classmethod
    def burn_evidence_overlay(
        cls,
        image_bytes: bytes,
        location_name: str,
        latitude: float,
        longitude: float,
        server_dt: datetime,
    ) -> bytes:
        """
        Bakes an authoritative tamper-proof evidence overlay onto the bottom-left
        corner of the selfie image before saving to database.
        """
        if not image_bytes:
            return image_bytes

        nparr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if img is None:
            return image_bytes

        h, w = img.shape[:2]

        tz = cls.get_server_timezone()
        local_dt = server_dt.astimezone(tz) if server_dt.tzinfo else pytz.utc.localize(server_dt).astimezone(tz)
        date_str = local_dt.strftime("%d %b %Y")
        time_str = local_dt.strftime("%I:%M:%S %p")

        if latitude is None or longitude is None:
            lat_str = "Unavailable"
            lon_str = "Unavailable"
        else:
            lat_str = f"{latitude:.6f}" if isinstance(latitude, (int, float)) else str(latitude)
            lon_str = f"{longitude:.6f}" if isinstance(longitude, (int, float)) else str(longitude)

        lines = [
            f"Location: {location_name or 'Field Location'}",
            f"Lat: {lat_str}",
            f"Long: {lon_str}",
            f"Date: {date_str}",
            f"Time: {time_str}"
        ]

        # Calculate font scale relative to image dimensions
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = max(0.45, min(w, h) / 1000.0 * 0.9)
        thickness = max(1, int(font_scale * 2.0))
        line_height = int(32 * font_scale + 8)

        padding = int(14 * font_scale + 6)
        max_line_w = 0
        for line in lines:
            (tw, th), _ = cv2.getTextSize(line, font, font_scale, thickness)
            if tw > max_line_w:
                max_line_w = tw

        box_w = max_line_w + (padding * 2)
        box_h = (line_height * len(lines)) + (padding * 2)

        # Bottom-left placement with 16px bottom margin and 16px left margin
        x1 = 16
        y2 = h - 16
        y1 = max(0, y2 - box_h)
        x2 = min(w, x1 + box_w)

        # Draw dark translucent overlay box
        overlay = img.copy()
        cv2.rectangle(overlay, (x1, y1), (x2, y2), (20, 20, 25), -1)
        cv2.rectangle(overlay, (x1, y1), (x2, y2), (70, 160, 255), 1) # Subtle accent border
        cv2.addWeighted(overlay, 0.75, img, 0.25, 0, img)

        # Draw text lines
        text_y = y1 + padding + int(line_height * 0.7)
        for idx, line in enumerate(lines):
            text_x = x1 + padding
            # Accent color for Date/Time vs Location
            text_color = (255, 255, 255)
            if "Time:" in line or "Date:" in line:
                text_color = (120, 230, 255) # Light cyan/amber for server time
            cv2.putText(img, line, (text_x, text_y), font, font_scale, text_color, thickness, cv2.LINE_AA)
            text_y += line_height

        # Re-encode to high quality JPEG
        encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 90]
        success, enc = cv2.imencode('.jpg', img, encode_param)
        if success:
            return enc.tobytes()
        return image_bytes

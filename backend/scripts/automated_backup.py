"""
Automated Database Backup Service for FieldStaff Attendance & Tracking
Performs scheduled backups (JSON & SQL dumps) of all tables.
Compatible with import_db_from_json.py restore utility.
"""

import os
import sys
import json
import base64
import subprocess
from datetime import datetime, date, time
from decimal import Decimal
from pathlib import Path

# Add project root to sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

try:
    from app.config import settings
    DB_HOST = settings.DB_HOST
    DB_PORT = settings.DB_PORT
    DB_USER = settings.DB_USER
    DB_PASSWORD = settings.DB_PASSWORD
    DB_NAME = settings.DB_NAME
except Exception:
    DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
    DB_PORT = int(os.getenv("DB_PORT", "3306"))
    DB_USER = os.getenv("DB_USER", "root")
    DB_PASSWORD = os.getenv("DB_PASSWORD", "user")
    DB_NAME = os.getenv("DB_NAME", "fieldstaff_attendance_db")

import pymysql

LOGS_DIR = PROJECT_ROOT / "logs"
LOGS_DIR.mkdir(parents=True, exist_ok=True)
LOG_FILE = LOGS_DIR / "backup_scheduler.log"

def log(msg: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    formatted = f"[{timestamp}] {msg}"
    print(formatted)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(formatted + "\n")

from datetime import datetime, date, time, timedelta

class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (datetime, date)):
            return obj.isoformat()
        if isinstance(obj, time):
            return obj.strftime("%H:%M:%S")
        if isinstance(obj, timedelta):
            # Format timedelta (e.g. 09:00:00)
            total_seconds = int(obj.total_seconds())
            hours, remainder = divmod(total_seconds, 3600)
            minutes, seconds = divmod(remainder, 60)
            return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
        if isinstance(obj, Decimal):
            return float(obj)
        if isinstance(obj, (bytes, bytearray)):
            return {
                "__blob__": True,
                "base64": base64.b64encode(obj).decode("ascii"),
                "size_bytes": len(obj)
            }
        return super().default(obj)

def run_backup():
    timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_root = PROJECT_ROOT / "exports"
    current_backup_dir = backup_root / f"backup_{timestamp_str}"
    json_dir = current_backup_dir / "json"
    sql_dir = current_backup_dir / "sql"
    latest_json_dir = backup_root / "latest" / "json"

    json_dir.mkdir(parents=True, exist_ok=True)
    sql_dir.mkdir(parents=True, exist_ok=True)
    latest_json_dir.mkdir(parents=True, exist_ok=True)

    log(f"=== Starting automated database backup for '{DB_NAME}' ===")

    conn = pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor
    )

    try:
        with conn.cursor() as cur:
            cur.execute("SHOW TABLES;")
            tables = [list(r.values())[0] for r in cur.fetchall()]

        log(f"Found {len(tables)} tables to export.")

        all_database_json = {}
        total_records = 0

        for table in tables:
            with conn.cursor() as cur:
                cur.execute(f"SELECT * FROM `{table}`;")
                rows = cur.fetchall()

            all_database_json[table] = rows
            total_records += len(rows)

            table_file = json_dir / f"{table}.json"
            with open(table_file, "w", encoding="utf-8") as f:
                json.dump(rows, f, cls=CustomJSONEncoder, indent=2)

            # Mirror to exports/latest/json
            latest_table_file = latest_json_dir / f"{table}.json"
            with open(latest_table_file, "w", encoding="utf-8") as f:
                json.dump(rows, f, cls=CustomJSONEncoder, indent=2)

        # Write combined database_complete.json
        combined_file = json_dir / "database_complete.json"
        with open(combined_file, "w", encoding="utf-8") as f:
            json.dump(all_database_json, f, cls=CustomJSONEncoder, indent=2)

        latest_combined_file = latest_json_dir / "database_complete.json"
        with open(latest_combined_file, "w", encoding="utf-8") as f:
            json.dump(all_database_json, f, cls=CustomJSONEncoder, indent=2)

        log(f"JSON export completed: {total_records} total records written across {len(tables)} tables.")

        # SQL Dump via mysqldump if available
        import shutil
        mysqldump_candidates = [
            r"C:\Program Files\MySQL\MySQL Workbench 8.0\mysqldump.exe",
            r"C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe",
            shutil.which("mysqldump")
        ]
        dump_bin = None
        for candidate in mysqldump_candidates:
            if candidate and Path(candidate).exists():
                dump_bin = str(Path(candidate).resolve())
                break

        if dump_bin:
            sql_file = sql_dir / f"{DB_NAME}_{timestamp_str}.sql"
            cmd = [
                dump_bin,
                f"--host={DB_HOST}",
                f"--port={DB_PORT}",
                f"--user={DB_USER}",
                f"--password={DB_PASSWORD}",
                "--routines",
                "--triggers",
                "--single-transaction",
                DB_NAME
            ]
            try:
                with open(sql_file, "w", encoding="utf-8") as out_f:
                    res = subprocess.run(cmd, stdout=out_f, stderr=subprocess.PIPE, text=True, timeout=60)
                if res.returncode == 0:
                    log(f"SQL dump successfully generated: {sql_file.name} ({sql_file.stat().st_size / 1024:.1f} KB)")
                else:
                    log(f"mysqldump warning: {res.stderr.strip()}")
            except Exception as ex:
                log(f"mysqldump execution skipped: {ex}")

        # Summary manifest
        manifest = {
            "timestamp": timestamp_str,
            "created_at": datetime.now().isoformat(),
            "database": DB_NAME,
            "table_count": len(tables),
            "record_count": total_records,
            "tables": {t: len(rows) for t, rows in all_database_json.items()}
        }
        with open(current_backup_dir / "backup_manifest.json", "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)

        log(f"Backup SUCCESS: Saved to {current_backup_dir.name} and synced to latest/json.")

        # Cleanup retention (keep last 56 backups = 7 days of 8x daily backups)
        existing_backups = sorted(
            [d for d in backup_root.glob("backup_*") if d.is_dir() and d.name != "backup_json_20261017"],
            key=lambda p: p.stat().st_mtime
        )
        if len(existing_backups) > 56:
            to_remove = existing_backups[:-56]
            for old_b in to_remove:
                try:
                    import shutil
                    shutil.rmtree(old_b)
                    log(f"Pruned old backup: {old_b.name}")
                except Exception as e:
                    log(f"Warning pruning {old_b.name}: {e}")

    finally:
        conn.close()

if __name__ == "__main__":
    run_backup()

"""
FieldStaff Attendance Database JSON Import Utility
Loads database tables from exported JSON dumps into MySQL / target database.
Decodes base64-encoded binary blobs (face embeddings, reference images, evidence).
"""

import os
import sys
import json
import base64
import pymysql
from datetime import datetime
from pathlib import Path

# Add backend directory to sys.path
BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

from app.config import settings
from app.database import Base
from sqlalchemy import create_engine

def import_json_to_db(json_file_path: str = None):
    if not json_file_path:
        json_file_path = str(BASE_DIR / "exports" / "latest" / "json" / "database_complete.json")

    json_path = Path(json_file_path).resolve()
    if not json_path.exists():
        print(f"[ERROR] JSON file not found at: {json_path}")
        sys.exit(1)

    print(f"[*] Reading JSON data from: {json_path}")
    with open(json_path, "r", encoding="utf-8") as f:
        db_data = json.load(f)

    # 1. Connect to MySQL server and ensure DB exists
    print(f"[*] Ensuring database '{settings.DB_NAME}' exists on {settings.DB_HOST}:{settings.DB_PORT}...")
    server_conn = pymysql.connect(
        host=settings.DB_HOST,
        port=settings.DB_PORT,
        user=settings.DB_USER,
        password=settings.DB_PASSWORD,
        charset="utf8mb4"
    )
    with server_conn.cursor() as cur:
        cur.execute(f"CREATE DATABASE IF NOT EXISTS `{settings.DB_NAME}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;")
    server_conn.commit()
    server_conn.close()

    # 2. Ensure all SQLAlchemy tables exist
    print("[*] Initializing table schemas...")
    mysql_url = f"mysql+pymysql://{settings.DB_USER}:{settings.DB_PASSWORD}@{settings.DB_HOST}:{settings.DB_PORT}/{settings.DB_NAME}?charset=utf8mb4"
    engine = create_engine(mysql_url)
    import app.models  # Register all models
    Base.metadata.create_all(engine)

    # 3. Connect to target database for inserting rows
    conn = pymysql.connect(
        host=settings.DB_HOST,
        port=settings.DB_PORT,
        user=settings.DB_USER,
        password=settings.DB_PASSWORD,
        database=settings.DB_NAME,
        charset="utf8mb4",
        autocommit=False
    )
    cur = conn.cursor()

    try:
        cur.execute("SET FOREIGN_KEY_CHECKS = 0;")
        # Enlarge BLOB columns to LONGBLOB for large evidence and face images
        cur.execute("ALTER TABLE attendance_requests MODIFY COLUMN evidence_image LONGBLOB NOT NULL;")
        cur.execute("ALTER TABLE face_templates MODIFY COLUMN face_image LONGBLOB NOT NULL;")
        cur.execute("ALTER TABLE face_enrollment_samples MODIFY COLUMN sample_image LONGBLOB NULL;")

        total_imported = 0
        for table_name, rows in db_data.items():
            if not rows:
                continue

            cur.execute(f"SHOW TABLES LIKE '{table_name}'")
            if not cur.fetchone():
                print(f"[!] Warning: Table '{table_name}' does not exist in target database. Skipping.")
                continue

            cur.execute(f"DESCRIBE `{table_name}`")
            db_cols = {r[0]: {"type": r[1].lower(), "null": r[2].lower() == "yes"} for r in cur.fetchall()}

            inserted_table_count = 0
            for row in rows:
                clean_row = {}
                for col, val in row.items():
                    if col not in db_cols:
                        continue

                    col_meta = db_cols[col]

                    # Decode base64 blobs
                    if isinstance(val, dict) and val.get("__blob__"):
                        b64_str = val.get("base64")
                        clean_row[col] = base64.b64decode(b64_str) if b64_str else None
                    elif isinstance(val, (dict, list)):
                        clean_row[col] = json.dumps(val)
                    elif val is None and not col_meta["null"]:
                        if "server_time" in col and "timestamp" in row and row["timestamp"]:
                            clean_row[col] = row["timestamp"]
                        elif "time" in col or "date" in col:
                            clean_row[col] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        elif "int" in col_meta["type"] or "tinyint" in col_meta["type"]:
                            clean_row[col] = 0
                        elif "float" in col_meta["type"] or "decimal" in col_meta["type"]:
                            clean_row[col] = 0.0
                        else:
                            clean_row[col] = ""
                    else:
                        clean_row[col] = val

                cols = list(clean_row.keys())
                placeholders = ", ".join(["%s"] * len(cols))
                col_names = ", ".join([f"`{c}`" for c in cols])
                values = [clean_row[c] for c in cols]

                sql = f"REPLACE INTO `{table_name}` ({col_names}) VALUES ({placeholders})"
                cur.execute(sql, values)
                inserted_table_count += 1

            print(f"[+] Imported {inserted_table_count:3d} rows into '{table_name}'")
            total_imported += inserted_table_count

        cur.execute("SET FOREIGN_KEY_CHECKS = 1;")
        conn.commit()
        print(f"\n[SUCCESS] Completed importing {total_imported} records into MySQL database '{settings.DB_NAME}'.")

    except Exception as e:
        conn.rollback()
        print(f"\n[ERROR] Database import failed: {e}")
        raise
    finally:
        cur.close()
        conn.close()

if __name__ == "__main__":
    target_json = sys.argv[1] if len(sys.argv) > 1 else None
    import_json_to_db(target_json)

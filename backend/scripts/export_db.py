"""
FieldStaff Attendance Database Export Utility
Exports all database tables into CSV, JSON, SQL dump, SQLite backup, and extracted images.
"""

import os
import sys
import json
import csv
import base64
import sqlite3
import shutil
from datetime import datetime
from pathlib import Path

def export_all(db_path: str, output_base_dir: str):
    db_file = Path(db_path).resolve()
    if not db_file.exists():
        print(f"Error: Database file not found at {db_file}")
        sys.exit(1)

    timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = Path(output_base_dir) / f"export_{timestamp_str}"
    latest_dir = Path(output_base_dir) / "latest"

    # Subdirectories
    csv_dir = out_dir / "csv"
    json_dir = out_dir / "json"
    sql_dir = out_dir / "sql"
    db_dir = out_dir / "database_file"
    images_dir = out_dir / "images"
    face_templates_img_dir = images_dir / "face_templates"
    enrollment_samples_img_dir = images_dir / "enrollment_samples"
    evidence_img_dir = images_dir / "evidence_requests"

    for d in [csv_dir, json_dir, sql_dir, db_dir, face_templates_img_dir, enrollment_samples_img_dir, evidence_img_dir]:
        d.mkdir(parents=True, exist_ok=True)

    print(f"=== Starting Database Export ===")
    print(f"Source DB: {db_file}")
    print(f"Output Directory: {out_dir}\n")

    conn = sqlite3.connect(str(db_file))
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Get employee_id mapping for meaningful image and record referencing
    user_map = {}
    try:
        cur.execute("SELECT id, employee_id, full_name FROM users")
        for u in cur.fetchall():
            user_map[u["id"]] = {
                "employee_id": u["employee_id"] or f"id_{u['id']}",
                "full_name": u["full_name"] or "Unknown"
            }
    except Exception as e:
        print(f"Warning loading users map: {e}")

    # 1. Direct SQLite Backup (.db)
    backup_db_path = db_dir / f"fieldstaff_attendance_backup_{timestamp_str}.db"
    print(f"[1/5] Creating SQLite binary snapshot: {backup_db_path.name}...")
    backup_conn = sqlite3.connect(str(backup_db_path))
    conn.backup(backup_conn)
    backup_conn.close()
    print(f"      Size: {backup_db_path.stat().st_size / 1024:.1f} KB")

    # 2. SQL Dump (.sql)
    sql_dump_path = sql_dir / f"fieldstaff_attendance_dump_{timestamp_str}.sql"
    print(f"[2/5] Creating complete SQL Dump: {sql_dump_path.name}...")
    with open(sql_dump_path, "w", encoding="utf-8") as f:
        for line in conn.iterdump():
            f.write(f"{line}\n")
    print(f"      Size: {sql_dump_path.stat().st_size / 1024:.1f} KB")

    # Fetch all tables
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    tables = [r[0] for r in cur.fetchall()]

    table_stats = {}
    all_json_data = {}
    extracted_images_count = {
        "face_templates": 0,
        "enrollment_samples": 0,
        "evidence_requests": 0
    }
    image_index = []

    print(f"[3/5] Exporting {len(tables)} tables to CSV and JSON...")
    for table in tables:
        # Schema info
        cur.execute(f"PRAGMA table_info({table})")
        col_info = cur.fetchall()
        col_names = [c[1] for c in col_info]
        col_types = {c[1]: (c[2] or "").upper() for c in col_info}

        cur.execute(f"SELECT * FROM {table}")
        rows = cur.fetchall()
        table_stats[table] = len(rows)

        # CSV Export
        csv_file_path = csv_dir / f"{table}.csv"
        json_table_rows = []

        with open(csv_file_path, "w", newline="", encoding="utf-8") as csvfile:
            writer = csv.writer(csvfile, quoting=csv.QUOTE_MINIMAL)
            writer.writerow(col_names)

            for row_idx, row in enumerate(rows):
                row_dict = dict(row)
                csv_row = []
                json_row = {}

                for col in col_names:
                    val = row_dict[col]
                    if isinstance(val, (bytes, bytearray, memoryview)):
                        b_val = bytes(val)
                        b_len = len(b_val)
                        col_type_decl = col_types.get(col, "")

                        # Determine if this is an image
                        is_jpeg = b_val.startswith(b'\xff\xd8\xff')
                        is_png = b_val.startswith(b'\x89PNG')
                        ext = ".jpg" if is_jpeg else (".png" if is_png else ".bin")

                        img_filename = None
                        # Check specific image columns to extract to disk
                        if table == "face_templates" and col == "face_image" and (is_jpeg or is_png):
                            uid = row_dict.get("user_id")
                            emp_code = user_map.get(uid, {}).get("employee_id", f"user_{uid}")
                            img_filename = f"user_{emp_code}_template_{row_dict.get('id')}{ext}"
                            target_img_path = face_templates_img_dir / img_filename
                            with open(target_img_path, "wb") as img_f:
                                img_f.write(b_val)
                            extracted_images_count["face_templates"] += 1
                            image_index.append({
                                "table": table,
                                "column": col,
                                "record_id": row_dict.get("id"),
                                "user_id": uid,
                                "employee_id": emp_code,
                                "filename": str(Path("images/face_templates") / img_filename),
                                "size_bytes": b_len
                            })

                        elif table == "face_enrollment_samples" and col == "sample_image" and (is_jpeg or is_png):
                            uid = row_dict.get("user_id")
                            s_idx = row_dict.get("sample_index", row_idx)
                            emp_code = user_map.get(uid, {}).get("employee_id", f"user_{uid}")
                            img_filename = f"user_{emp_code}_sample_{s_idx}_id_{row_dict.get('id')}{ext}"
                            target_img_path = enrollment_samples_img_dir / img_filename
                            with open(target_img_path, "wb") as img_f:
                                img_f.write(b_val)
                            extracted_images_count["enrollment_samples"] += 1
                            image_index.append({
                                "table": table,
                                "column": col,
                                "record_id": row_dict.get("id"),
                                "user_id": uid,
                                "employee_id": emp_code,
                                "filename": str(Path("images/enrollment_samples") / img_filename),
                                "size_bytes": b_len
                            })

                        elif table == "attendance_requests" and col == "evidence_image" and (is_jpeg or is_png):
                            uid = row_dict.get("user_id")
                            req_date = str(row_dict.get("request_date") or "unknown_date")
                            emp_code = user_map.get(uid, {}).get("employee_id", f"user_{uid}")
                            img_filename = f"request_{row_dict.get('id')}_emp_{emp_code}_{req_date}{ext}"
                            target_img_path = evidence_img_dir / img_filename
                            with open(target_img_path, "wb") as img_f:
                                img_f.write(b_val)
                            extracted_images_count["evidence_requests"] += 1
                            image_index.append({
                                "table": table,
                                "column": col,
                                "record_id": row_dict.get("id"),
                                "user_id": uid,
                                "employee_id": emp_code,
                                "filename": str(Path("images/evidence_requests") / img_filename),
                                "size_bytes": b_len
                            })

                        if img_filename:
                            csv_row.append(f"[IMAGE: {img_filename} ({b_len} bytes)]")
                        elif "EMBEDDING" in col.upper():
                            csv_row.append(f"[EMBEDDING_VECTOR: {b_len} bytes]")
                        else:
                            csv_row.append(f"[BINARY_BLOB: {b_len} bytes]")

                        # JSON representation: base64 representation with metadata
                        json_row[col] = {
                            "__blob__": True,
                            "type": "image" if (is_jpeg or is_png) else ("embedding" if "EMBEDDING" in col.upper() else "binary"),
                            "size_bytes": b_len,
                            "extracted_file": img_filename,
                            "base64": base64.b64encode(b_val).decode("ascii")
                        }
                    else:
                        csv_row.append("" if val is None else str(val))
                        # Try parsing JSON columns if applicable
                        if isinstance(val, str) and (val.startswith("{") or val.startswith("[")):
                            try:
                                json_row[col] = json.loads(val)
                            except Exception:
                                json_row[col] = val
                        else:
                            json_row[col] = val

                writer.writerow(csv_row)
                json_table_rows.append(json_row)

        # Write per-table JSON
        json_file_path = json_dir / f"{table}.json"
        with open(json_file_path, "w", encoding="utf-8") as jf:
            json.dump(json_table_rows, jf, indent=2, default=str)

        all_json_data[table] = json_table_rows
        print(f"  - Table '{table}': {len(rows)} records -> CSV & JSON")

    # 4. Consolidated JSON export
    print(f"\n[4/5] Writing consolidated database JSON...")
    all_json_path = json_dir / "database_complete.json"
    with open(all_json_path, "w", encoding="utf-8") as jf:
        json.dump(all_json_data, jf, indent=2, default=str)
    print(f"      Size: {all_json_path.stat().st_size / 1024:.1f} KB")

    # Image index CSV
    if image_index:
        img_index_path = images_dir / "images_catalog.csv"
        with open(img_index_path, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["table", "column", "record_id", "user_id", "employee_id", "filename", "size_bytes"])
            w.writeheader()
            w.writerows(image_index)
        print(f"      Extracted {len(image_index)} total image files into {images_dir}")

    # 5. Create latest symlink or copy
    print(f"[5/5] Updating '{latest_dir}' folder...")
    if latest_dir.exists():
        try:
            shutil.rmtree(latest_dir)
        except Exception:
            pass
    try:
        shutil.copytree(out_dir, latest_dir)
    except Exception as e:
        print(f"      Warning creating latest copy: {e}")

    # Generate Summary Markdown
    summary_md_path = out_dir / "EXPORT_SUMMARY.md"
    summary_content = f"""# FieldStaff Database Export Summary
**Export Timestamp:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
**Source Database:** `{db_file}`
**Export Directory:** `{out_dir}`

---

## 1. Export Formats & File Locations

| Format | Path | Description |
|---|---|---|
| **SQLite DB Snapshot** | `database_file/{backup_db_path.name}` | Complete binary backup of the database ({backup_db_path.stat().st_size / 1024:.1f} KB) |
| **SQL Dump** | `sql/{sql_dump_path.name}` | SQL statements with full schema & insert rows ({sql_dump_path.stat().st_size / 1024:.1f} KB) |
| **Complete JSON** | `json/database_complete.json` | All tables in a single structured JSON ({all_json_path.stat().st_size / 1024:.1f} KB) |
| **CSV Tables** | `csv/*.csv` | Individual CSV spreadsheets for all {len(tables)} tables |
| **Table JSONs** | `json/*.json` | Individual JSON file per table |
| **Extracted Images** | `images/` | {len(image_index)} extracted JPEG/PNG photos (templates, samples, evidence) |

---

## 2. Table Record Counts

| Table Name | Records Exported | CSV File | JSON File |
|---|---|---|---|
"""
    for tbl, count in table_stats.items():
        summary_content += f"| **{tbl}** | {count} rows | [`{tbl}.csv`](file:///{str(csv_dir / (tbl + '.csv')).replace(chr(92), '/')} ) | [`{tbl}.json`](file:///{str(json_dir / (tbl + '.json')).replace(chr(92), '/')} ) |\n"

    summary_content += f"""
---

## 3. Extracted Photos & Biometrics

- **Face Templates (Enrolled Profiles):** {extracted_images_count['face_templates']} photos in `images/face_templates/`
- **Enrollment Samples (Angle/Lighting captures):** {extracted_images_count['enrollment_samples']} photos in `images/enrollment_samples/`
- **Attendance Request Evidence:** {extracted_images_count['evidence_requests']} photos in `images/evidence_requests/`
- **Catalog Index:** `images/images_catalog.csv`

---

## 4. How to Use These Files

1. **Excel / Spreadsheets:** Open any `.csv` file directly in Microsoft Excel, LibreOffice, or Google Sheets.
2. **SQLite Database Browser:** Open `database_file/{backup_db_path.name}` with DB Browser for SQLite or SQLite CLI.
3. **Database Restore:** Execute `sql/{sql_dump_path.name}` into a new SQLite database using:
   ```bash
   sqlite3 new_database.db < {sql_dump_path.name}
   ```
4. **Web / Scripts Integration:** Parse `json/database_complete.json` or individual table JSON files directly with Python, Node.js, or Dart.
"""

    with open(summary_md_path, "w", encoding="utf-8") as f:
        f.write(summary_content)

    # Copy summary to latest as well
    latest_summary = latest_dir / "EXPORT_SUMMARY.md"
    if latest_dir.exists():
        with open(latest_summary, "w", encoding="utf-8") as f:
            f.write(summary_content)

    conn.close()

    print(f"\n Export Completed Successfully!")
    print(f"Summary written to: {summary_md_path}")
    return out_dir

if __name__ == "__main__":
    db_file_arg = sys.argv[1] if len(sys.argv) > 1 else "backend/fieldstaff_attendance.db"
    out_dir_arg = sys.argv[2] if len(sys.argv) > 2 else "backend/exports"
    export_all(db_file_arg, out_dir_arg)

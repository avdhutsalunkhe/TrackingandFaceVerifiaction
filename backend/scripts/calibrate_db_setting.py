import sqlite3

conn = sqlite3.connect('fieldstaff_attendance.db')
cursor = conn.cursor()
cursor.execute("UPDATE system_settings SET value = '0.60' WHERE key = 'SIMILARITY_THRESHOLD'")
conn.commit()
cursor.execute("SELECT key, value FROM system_settings WHERE key = 'SIMILARITY_THRESHOLD'")
print('Updated setting:', cursor.fetchone())
conn.close()

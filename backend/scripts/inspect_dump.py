import numpy as np

with open('exports/latest/sql/fieldstaff_attendance_dump_20260922_100836.sql', 'r', encoding='utf-8') as f:
    lines = f.readlines()

line = lines[706]
idx1 = line.find("X'")
idx2 = line.find("'", idx1 + 2)
idx3 = line.find("X'", idx2 + 1)
idx4 = line.find("'", idx3 + 2)

emb_bytes = bytes.fromhex(line[idx1+2:idx2])
img_bytes = bytes.fromhex(line[idx3+2:idx4])
print("Embedding len:", len(emb_bytes), "Image len:", len(img_bytes))

with open("dump_user6_face.jpg", "wb") as out_f:
    out_f.write(img_bytes)

emb = np.frombuffer(emb_bytes, dtype=np.float32)
print("Embedding norm:", np.linalg.norm(emb))

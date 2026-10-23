import http.server
import json
import os
import sqlite3
import sys
import urllib.parse

PORT = 8765
DB_PATH = os.path.join(os.path.dirname(__file__), "india_gazetteer.db")

class MapRequestHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = urllib.parse.parse_qs(parsed.query)

        if path == "/api/stats":
            self.handle_stats()
        elif path == "/api/points":
            self.handle_points(params)
        elif path == "/api/search":
            self.handle_search(params)
        elif path == "/api/heatmap":
            self.handle_heatmap()
        elif path == "/" or path == "/index.html":
            self.serve_map_html()
        else:
            super().do_GET()

    def get_db(self):
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        return conn

    def handle_stats(self):
        try:
            conn = self.get_db()
            cur = conn.cursor()
            total = cur.execute("SELECT COUNT(*) FROM places").fetchone()[0]
            classes = cur.execute(
                "SELECT feature_class, COUNT(*) as cnt FROM places GROUP BY feature_class ORDER BY cnt DESC"
            ).fetchall()
            top_cities = cur.execute(
                "SELECT name, latitude, longitude, population FROM places WHERE feature_class = 'P' ORDER BY population DESC LIMIT 15"
            ).fetchall()
            conn.close()

            payload = {
                "total_points": total,
                "classes": [{"class": r["feature_class"], "count": r["cnt"]} for r in classes],
                "top_cities": [dict(r) for r in top_cities]
            }
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(json.dumps(payload).encode("utf-8"))
        except Exception as e:
            self.send_error(500, str(e))

    def handle_points(self, params):
        try:
            min_lat = float(params.get("min_lat", [6.0])[0])
            max_lat = float(params.get("max_lat", [38.0])[0])
            min_lng = float(params.get("min_lng", [68.0])[0])
            max_lng = float(params.get("max_lng", [98.0])[0])
            limit = min(int(params.get("limit", [2500])[0]), 10000)
            classes_str = params.get("classes", ["P,H,T,S,A,L,V,R"])[0]
            classes = [c.strip().upper() for c in classes_str.split(",") if c.strip()]
            min_pop = int(params.get("min_pop", [0])[0])

            placeholders = ",".join("?" for _ in classes)
            query = f"""
                SELECT geonameid, name, latitude, longitude, feature_class, feature_code, population, elevation, dem
                FROM places
                WHERE latitude BETWEEN ? AND ?
                  AND longitude BETWEEN ? AND ?
                  AND feature_class IN ({placeholders})
                  AND population >= ?
                ORDER BY population DESC, geonameid ASC
                LIMIT ?
            """
            args = [min_lat, max_lat, min_lng, max_lng] + classes + [min_pop, limit]

            conn = self.get_db()
            cur = conn.cursor()
            rows = cur.execute(query, args).fetchall()
            conn.close()

            points = []
            for r in rows:
                points.append({
                    "id": r["geonameid"],
                    "name": r["name"],
                    "lat": r["latitude"],
                    "lng": r["longitude"],
                    "fc": r["feature_class"],
                    "fcode": r["feature_code"],
                    "pop": r["population"],
                    "elev": r["elevation"] or r["dem"]
                })

            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(json.dumps({"count": len(points), "points": points}).encode("utf-8"))
        except Exception as e:
            self.send_error(500, str(e))

    def handle_search(self, params):
        try:
            q = params.get("q", [""])[0].strip()
            if not q:
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"[]")
                return

            conn = self.get_db()
            cur = conn.cursor()
            rows = cur.execute(
                """
                SELECT geonameid, name, latitude, longitude, feature_class, feature_code, population, admin1_code
                FROM places
                WHERE name LIKE ? || '%' OR asciiname LIKE ? || '%'
                ORDER BY population DESC, length(name) ASC
                LIMIT 15
                """,
                (q, q)
            ).fetchall()
            conn.close()

            results = [dict(r) for r in rows]
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(json.dumps(results).encode("utf-8"))
        except Exception as e:
            self.send_error(500, str(e))

    def handle_heatmap(self):
        try:
            # Nationwide sampled coordinates for fast sub-sampling
            conn = self.get_db()
            cur = conn.cursor()
            rows = cur.execute(
                """
                SELECT latitude, longitude,
                       CASE WHEN population > 100000 THEN 1.0
                            WHEN population > 10000 THEN 0.7
                            WHEN feature_class = 'P' THEN 0.4
                            ELSE 0.2 END as weight
                FROM places
                WHERE (geonameid % 12 == 0) OR population > 50000
                LIMIT 40000
                """
            ).fetchall()
            conn.close()

            points = [[round(r[0], 4), round(r[1], 4), r[2]] for r in rows]
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(json.dumps(points).encode("utf-8"))
        except Exception as e:
            self.send_error(500, str(e))

    def serve_map_html(self):
        html_file = os.path.join(os.path.dirname(__file__), "index.html")
        if os.path.exists(html_file):
            with open(html_file, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        else:
            self.send_error(404, "index.html not found")

if __name__ == "__main__":
    server_address = ("127.0.0.1", PORT)
    httpd = http.server.ThreadingHTTPServer(server_address, MapRequestHandler)
    print(f"India Gazetteer Map Server running at http://127.0.0.1:{PORT}")
    httpd.serve_forever()

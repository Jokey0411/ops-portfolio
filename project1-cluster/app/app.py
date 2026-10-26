#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
极简业务后端：模拟 Web 业务集群里的应用进程
作用：提供 HTTP 接口查询/写入 MySQL，用来验证 LB 轮询、主从同步、读写分离
"""
import os
import json
import time
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import pymysql

DB_HOST = os.getenv("DB_HOST", "node1-db")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "app")
DB_PASS = os.getenv("DB_PASS", "App@123456")
DB_NAME = os.getenv("DB_NAME", "shop")
NODE_ID = os.getenv("NODE_ID", "unknown")
READ_ONLY = os.getenv("READ_ONLY", "0") == "1"


def get_conn():
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASS,
        database=DB_NAME, charset="utf8mb4", connect_timeout=5, autocommit=True,
    )


def wait_for_db(max_retry=40):
    """MySQL 容器启动需要 30~60 秒，应用必须自己等，否则 compose 起来就崩"""
    for i in range(max_retry):
        try:
            conn = get_conn()
            conn.close()
            print(f"[app] DB {DB_HOST} ready after {i * 2}s", flush=True)
            return True
        except Exception as e:
            print(f"[app] waiting DB ({i + 1}/{max_retry}): {e}", flush=True)
            time.sleep(2)
    print("[app] DB unreachable, start in degraded mode", flush=True)
    return False


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _json(self, code, data):
        body = json.dumps(data, ensure_ascii=False, default=str).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"[{NODE_ID}] {self.address_string()} {fmt % args}", flush=True)

    # ---------- GET ----------
    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)

        if u.path in ("/", "/health"):
            db_ok, db_err = self._db_probe()
            self._json(200 if db_ok else 503, {
                "node": NODE_ID,
                "hostname": socket.gethostname(),
                "db_host": DB_HOST,
                "db": "ok" if db_ok else f"down: {db_err}",
                "read_only": READ_ONLY,
                "time": time.strftime("%Y-%m-%d %H:%M:%S"),
            })
            return

        if u.path == "/api/orders":
            user_id = int(q.get("user_id", ["1"])[0])
            try:
                conn = get_conn()
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT id, user_id, product, amount, status, created_at "
                        "FROM orders WHERE user_id=%s ORDER BY id DESC LIMIT 10", (user_id,))
                    rows = cur.fetchall()
                conn.close()
                self._json(200, {"node": NODE_ID, "count": len(rows), "data": rows})
            except Exception as e:
                self._json(500, {"node": NODE_ID, "error": str(e)})
            return

        if u.path == "/api/stats":
            """验证主从同步用：返回订单总数，主库写入后去从库查这个接口比对"""
            try:
                conn = get_conn()
                with conn.cursor() as cur:
                    cur.execute("SELECT COUNT(*) FROM orders")
                    total = cur.fetchone()[0]
                    cur.execute("SELECT MAX(id) FROM orders")
                    maxid = cur.fetchone()[0]
                conn.close()
                self._json(200, {"node": NODE_ID, "db": DB_HOST,
                                 "total_orders": total, "max_id": maxid})
            except Exception as e:
                self._json(500, {"node": NODE_ID, "error": str(e)})
            return

        self._json(404, {"error": "not found", "path": u.path})

    # ---------- POST ----------
    def do_POST(self):
        u = urlparse(self.path)

        if u.path == "/api/order":
            if READ_ONLY:
                # 从库节点拒绝写 —— 演示读写分离时写请求必须路由到主库
                self._json(403, {"node": NODE_ID, "error":
                                 "this node is read-only, write must go to master"})
                return
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            try:
                conn = get_conn()
                with conn.cursor() as cur:
                    cur.execute(
                        "INSERT INTO orders (user_id, product, amount, status) "
                        "VALUES (%s,%s,%s,%s)",
                        (body.get("user_id", 1), body.get("product", "test-item"),
                         body.get("amount", 9.9), body.get("status", "paid")))
                    new_id = cur.lastrowid
                conn.close()
                self._json(201, {"node": NODE_ID, "inserted_id": new_id})
            except Exception as e:
                self._json(500, {"node": NODE_ID, "error": str(e)})
            return

        self._json(404, {"error": "not found"})

    def _db_probe(self):
        try:
            conn = get_conn()
            conn.close()
            return True, None
        except Exception as e:
            return False, str(e)


if __name__ == "__main__":
    wait_for_db()
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print(f"[app] {NODE_ID} listening on 8080, db={DB_HOST}", flush=True)
    server.serve_forever()

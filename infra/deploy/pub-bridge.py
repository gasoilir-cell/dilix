#!/usr/bin/env python3
"""پروکسیِ CONNECT برای رساندنِ `flutter pub` سرور به آینهٔ pub.

سرورِ production نه به pub.dev می‌رسد (۴۰۳ جغرافیایی) و نه اتصالِ مستقیمِ TLS
به آینه‌ها از آن بالا می‌آید (در SYN-SENT می‌ماند). این پروکسی داخلِ کانتینر
اجرا می‌شود و با یک تونلِ معکوسِ SSH (`-R 8888:127.0.0.1:8888`) روی سرور در
دسترس قرار می‌گیرد.

فقط CONNECT را پیاده می‌کند؛ چیزی که pub لازم دارد همین است.
"""
from __future__ import annotations

import selectors
import socket
import sys
import threading

HOST, PORT = "127.0.0.1", 8888
# فقط میزبان‌های لازمِ زنجیرهٔ بیلد. باز گذاشتنِ کامل، این پروکسی را به یک
# رله‌ی عمومی روی شبکه‌ی سرور تبدیل می‌کرد.
ALLOWED = (
    "mirrors.tuna.tsinghua.edu.cn",
    "pub.flutter-io.cn",
    "storage.flutter-io.cn",
    "pub.dev",
    "storage.googleapis.com",
)


def _pipe(a: socket.socket, b: socket.socket) -> None:
    sel = selectors.DefaultSelector()
    sel.register(a, selectors.EVENT_READ, b)
    sel.register(b, selectors.EVENT_READ, a)
    try:
        while True:
            for key, _ in sel.select(timeout=180):
                data = key.fileobj.recv(65536)
                if not data:
                    return
                key.data.sendall(data)
            else:
                if not sel.get_map():
                    return
    except OSError:
        pass
    finally:
        sel.close()


def _handle(client: socket.socket) -> None:
    upstream = None
    try:
        client.settimeout(30)
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = client.recv(4096)
            if not chunk:
                return
            head += chunk
            if len(head) > 16384:
                return
        line = head.split(b"\r\n", 1)[0].decode("latin-1")
        method, target, *_ = line.split(" ")
        if method != "CONNECT":
            client.sendall(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
            return
        host, _, port = target.partition(":")
        if host not in ALLOWED:
            client.sendall(b"HTTP/1.1 403 Forbidden\r\n\r\n")
            return
        upstream = socket.create_connection((host, int(port or 443)), timeout=30)
        client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        client.settimeout(None)
        upstream.settimeout(None)
        _pipe(client, upstream)
    except OSError:
        pass
    finally:
        for s in (client, upstream):
            if s:
                try:
                    s.close()
                except OSError:
                    pass


def main() -> None:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(64)
    print(f"pub-bridge listening on {HOST}:{PORT}", flush=True)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=_handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)

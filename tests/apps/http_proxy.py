#!/usr/bin/env python3
"""Minimal HTTP/CONNECT proxy for testing. Logs proxied requests to stdout."""

import http.server
import select
import socket
import socketserver
import sys
import urllib.request


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self._forward()

    def do_POST(self):
        self._forward()

    def do_HEAD(self):
        self._forward()

    def _forward(self):
        print(f"PROXIED {self.command} {self.path}", flush=True)
        try:
            body = None
            cl = self.headers.get("Content-Length")
            if cl:
                body = self.rfile.read(int(cl))
            req = urllib.request.Request(
                self.path, data=body, method=self.command
            )
            for key, val in self.headers.items():
                if key.lower() in ("host", "connection"):
                    continue
                req.add_header(key, val)
            with urllib.request.urlopen(req, timeout=30) as resp:
                self.send_response(resp.status)
                for key, val in resp.headers.items():
                    self.send_header(key, val)
                self.end_headers()
                self.wfile.write(resp.read())
        except Exception as e:
            self.send_error(502, str(e))

    def do_CONNECT(self):
        print(f"PROXIED CONNECT {self.path}", flush=True)
        host, port = self.path.split(":")
        try:
            remote = socket.create_connection((host, int(port)), timeout=10)
        except Exception as e:
            self.send_error(502, str(e))
            return

        # Send 200 directly on the raw socket to avoid wfile buffering issues
        self.request.sendall(
            b"HTTP/1.1 200 Connection Established\r\n\r\n"
        )

        # Drain any buffered data in rfile that belongs to the tunnel
        if hasattr(self.rfile, "peek"):
            buffered = self.rfile.peek(8192)
            if buffered:
                remote.sendall(buffered)
                self.rfile.read(len(buffered))

        # Bidirectional tunnel
        conns = [self.request, remote]
        try:
            while conns:
                readable, _, _ = select.select(conns, [], [], 60)
                if not readable:
                    break
                for s in readable:
                    data = s.recv(65536)
                    if not data:
                        conns = []
                        break
                    if s is self.request:
                        remote.sendall(data)
                    else:
                        self.request.sendall(data)
        finally:
            remote.close()

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8888
    srv = socketserver.ThreadingTCPServer(("0.0.0.0", port), ProxyHandler)
    print(f"PROXY_READY {port}", flush=True)
    srv.serve_forever()

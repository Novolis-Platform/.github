#!/usr/bin/env python3
"""Serve the logo-graph visual editor and save spec/logo-graph.json."""
from __future__ import annotations

import argparse
import base64
import json
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

BRAND = Path(__file__).resolve().parent.parent
SPEC = BRAND / "spec"
GRAPH_PATH = SPEC / "logo-graph.json"
EDITOR_HTML = SPEC / "graph-editor.html"
REF_IMAGE = BRAND / "reference" / "icon-crop.png"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        if args and str(args[0]).startswith("GET /api/ping"):
            return
        super().log_message(fmt, *args)

    def _send_json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _read_json_body(self) -> dict | None:
        length = int(self.headers.get("Content-Length", 0))
        if length <= 0:
            return None
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/api/ping":
            self._send_json(200, {"ok": True})
            return
        if path == "/api/bootstrap":
            graph = json.loads(GRAPH_PATH.read_text(encoding="utf-8"))
            ref_b64 = base64.standard_b64encode(REF_IMAGE.read_bytes()).decode("ascii")
            self._send_json(
                200,
                {
                    "graph": graph,
                    "reference": f"data:image/png;base64,{ref_b64}",
                    "reference_path": str(REF_IMAGE),
                },
            )
            return

        rel = {
            "/": "graph-editor.html",
            "/graph-editor.html": "graph-editor.html",
            "/logo-graph.json": "logo-graph.json",
            "/reference/icon-crop.png": "../reference/icon-crop.png",
        }.get(path)

        if rel is None:
            self.send_error(404)
            return

        file_path = (SPEC / rel).resolve() if not rel.startswith("..") else (BRAND / rel[3:]).resolve()
        if not file_path.is_file():
            self.send_error(404, f"missing {file_path}")
            return

        ctype = {
            ".html": "text/html; charset=utf-8",
            ".json": "application/json; charset=utf-8",
            ".png": "image/png",
        }.get(file_path.suffix, "application/octet-stream")

        data = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self) -> None:
        if urlparse(self.path).path != "/api/save":
            self.send_error(404)
            return
        try:
            payload = self._read_json_body()
            if not payload or payload.get("schema") != "novolis-logo-graph/1":
                self._send_json(400, {"error": "expected novolis-logo-graph/1"})
                return
            GRAPH_PATH.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
            self._send_json(200, {"ok": True, "path": str(GRAPH_PATH)})
            print(f"saved {GRAPH_PATH}")
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid json"})
        except OSError as exc:
            self._send_json(500, {"error": str(exc)})


class _ReuseHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True


def _port_candidates(preferred: int) -> list[int]:
    """Ports to try; avoids low ranges often blocked on Windows."""
    out: list[int] = []
    seen: set[int] = set()

    def add(p: int) -> None:
        if p > 0 and p not in seen:
            seen.add(p)
            out.append(p)

    add(preferred)
    for base in (38472, 41765, 49200):
        for offset in range(24):
            add(base + offset)
    return out


def _bind_server(host: str, preferred: int) -> tuple[_ReuseHTTPServer, int]:
    last_err: OSError | None = None
    for port in _port_candidates(preferred):
        try:
            server = _ReuseHTTPServer((host, port), Handler)
            return server, port
        except OSError as exc:
            last_err = exc
            continue
    msg = f"could not bind {host} (tried {len(_port_candidates(preferred))} ports)"
    if last_err is not None:
        msg += f": {last_err}"
    raise SystemExit(msg)


def main() -> None:
    parser = argparse.ArgumentParser(description="Novolis logo-graph visual editor")
    parser.add_argument(
        "--port",
        type=int,
        default=38472,
        help="Preferred port (default 38472; auto-fallback if blocked or in use)",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Bind address (default 127.0.0.1)")
    parser.add_argument("--no-open", action="store_true", help="Do not open a browser tab")
    args = parser.parse_args()

    for p in (EDITOR_HTML, GRAPH_PATH, REF_IMAGE):
        if not p.is_file():
            raise SystemExit(f"missing required file: {p}")

    server, port = _bind_server(args.host, args.port)
    if port != args.port:
        print(f"note: port {args.port} unavailable, using {port}")
    url = f"http://{args.host}:{port}/"
    print(f"logo-graph editor: {url}")
    print("  Enter = confirm shape   Backspace = reset shape   Z = undo click")
    print(f"  writes: {GRAPH_PATH}")
    if not args.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()

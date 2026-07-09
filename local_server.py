"""Local development server for the MVP application.

This server serves static frontend files and forwards local API requests to the
Lambda handler. It is intended for local verification only.
"""

from __future__ import annotations

import logging
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from api.app import handler

logger = logging.getLogger(__name__)

HOST = "127.0.0.1"
PORT = 3000
PROJECT_ROOT = Path(__file__).resolve().parent
FRONTEND_DIR = PROJECT_ROOT / "frontend"
HTTP_METHOD_GET = "GET"


class LocalRequestHandler(SimpleHTTPRequestHandler):
    """Serve frontend files and route API requests to the Lambda handler."""

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        """Initialize the request handler with the frontend directory."""

        super().__init__(*args, directory=str(FRONTEND_DIR), **kwargs)

    def do_GET(self) -> None:
        """Handle GET requests."""

        parsed_url = urlparse(self.path)

        if parsed_url.path.startswith("/api/"):
            self.handle_api_request(parsed_url.path, parsed_url.query)
            return

        super().do_GET()

    def handle_api_request(self, path: str, query: str) -> None:
        """Route a local API request to the Lambda handler.

        Args:
            path: Request path.
            query: Raw query string.
        """

        query_params = {
            key: values[0]
            for key, values in parse_qs(query, keep_blank_values=True).items()
        }
        event = {
            "rawPath": path,
            "requestContext": {
                "http": {
                    "method": HTTP_METHOD_GET,
                    "path": path,
                }
            },
            "queryStringParameters": query_params,
        }

        response = handler(event, None)
        status_code = response["statusCode"]
        headers = response.get("headers", {})
        body = response.get("body", "")

        self.send_response(status_code)
        for name, value in headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body.encode("utf-8"))


def main() -> None:
    """Start the local development server."""

    logging.basicConfig(level=logging.INFO)
    server = ThreadingHTTPServer((HOST, PORT), LocalRequestHandler)
    logger.info("Local server started: http://%s:%s", HOST, PORT)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Local server stopped")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()

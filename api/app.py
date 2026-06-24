"""Lambda handler for the dummy book search API."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any, Literal, TypedDict

try:
    from data.books import BOOK_MARKET_BOOKS, OLD_BOOKS_ONLINE_BOOKS, Book
except ModuleNotFoundError:
    from .data.books import BOOK_MARKET_BOOKS, OLD_BOOKS_ONLINE_BOOKS, Book

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SITE_TIMEOUT_SECONDS = 3.0
BOOK_MARKET_DELAY_SECONDS = 0.8
OLD_BOOKS_ONLINE_DELAY_SECONDS = 1.4
MAX_QUERY_LENGTH = 80

BOOK_MARKET_ID = "book_market"
BOOK_MARKET_NAME = "Book Market"
OLD_BOOKS_ONLINE_ID = "old_books_online"
OLD_BOOKS_ONLINE_NAME = "Old Books Online"

Scenario = Literal[
    "book_market_error",
    "old_books_online_error",
    "book_market_timeout",
    "old_books_online_timeout",
]


class SiteResult(TypedDict):
    """Search result for one dummy bookstore."""

    site_id: str
    site_name: str
    status: Literal["success", "error"]
    result_count: int
    results: list[Book]
    error: str | None


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Handle Lambda Function URL requests.

    Args:
        event: Lambda Function URL event.
        context: Lambda runtime context.

    Returns:
        API Gateway compatible HTTP response.
    """

    del context

    path = event.get("rawPath", "/")
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    logger.info(
        json.dumps(
            {
                "message": "request_received",
                "method": method,
                "path": path,
            },
            ensure_ascii=False,
        )
    )

    if method != "GET":
        return build_response(405, {"message": "method not allowed"})

    if path in {"/api/health", "/health"}:
        return build_response(200, {"status": "ok"})

    if path not in {"/api/books", "/books"}:
        return build_response(404, {"message": "not found"})

    query_params = event.get("queryStringParameters") or {}
    query = normalize_query(query_params.get("q"))
    scenario = query_params.get("scenario")

    if not query:
        return build_response(400, {"message": "query parameter 'q' is required"})

    if len(query) > MAX_QUERY_LENGTH:
        return build_response(
            400,
            {"message": f"query parameter 'q' must be {MAX_QUERY_LENGTH} characters or fewer"},
        )

    started_at = time.perf_counter()
    site_results = asyncio.run(search_all_sites(query, scenario))
    elapsed_ms = round((time.perf_counter() - started_at) * 1000)
    books = [book for site in site_results for book in site["results"]]

    payload = {
        "query": query,
        "results": books,
        "sites": [
            {
                "site_id": site["site_id"],
                "site_name": site["site_name"],
                "status": site["status"],
                "result_count": site["result_count"],
                "error": site["error"],
            }
            for site in site_results
        ],
        "elapsed_ms": elapsed_ms,
    }

    logger.info(
        json.dumps(
            {
                "message": "search_completed",
                "query": query,
                "result_count": len(books),
                "elapsed_ms": elapsed_ms,
            },
            ensure_ascii=False,
        )
    )

    return build_response(200, payload)


async def search_all_sites(query: str, scenario: str | None) -> list[SiteResult]:
    """Search all dummy bookstores concurrently.

    Args:
        query: Normalized search query.
        scenario: Optional scenario name for manual verification.

    Returns:
        Search results grouped by site.
    """

    tasks = [
        search_site_with_timeout(
            site_id=BOOK_MARKET_ID,
            site_name=BOOK_MARKET_NAME,
            books=BOOK_MARKET_BOOKS,
            delay_seconds=BOOK_MARKET_DELAY_SECONDS,
            query=query,
            scenario=scenario,
        ),
        search_site_with_timeout(
            site_id=OLD_BOOKS_ONLINE_ID,
            site_name=OLD_BOOKS_ONLINE_NAME,
            books=OLD_BOOKS_ONLINE_BOOKS,
            delay_seconds=OLD_BOOKS_ONLINE_DELAY_SECONDS,
            query=query,
            scenario=scenario,
        ),
    ]
    return await asyncio.gather(*tasks)


async def search_site_with_timeout(
    *,
    site_id: str,
    site_name: str,
    books: list[Book],
    delay_seconds: float,
    query: str,
    scenario: str | None,
) -> SiteResult:
    """Search one dummy bookstore with timeout and error handling.

    Args:
        site_id: Dummy bookstore ID.
        site_name: Dummy bookstore display name.
        books: Books owned by the dummy bookstore.
        delay_seconds: Artificial response delay.
        query: Normalized search query.
        scenario: Optional scenario name for manual verification.

    Returns:
        Site-level search result.
    """

    try:
        results = await asyncio.wait_for(
            search_site(
                site_id=site_id,
                books=books,
                delay_seconds=delay_seconds,
                query=query,
                scenario=scenario,
            ),
            timeout=SITE_TIMEOUT_SECONDS,
        )
        return {
            "site_id": site_id,
            "site_name": site_name,
            "status": "success",
            "result_count": len(results),
            "results": results,
            "error": None,
        }
    except TimeoutError:
        logger.warning(
            json.dumps(
                {
                    "message": "site_search_timeout",
                    "site_id": site_id,
                },
                ensure_ascii=False,
            )
        )
        return build_site_error(site_id, site_name, "site request timed out")
    except Exception as error:
        logger.exception("site_search_failed", extra={"site_id": site_id})
        return build_site_error(site_id, site_name, str(error))


async def search_site(
    *,
    site_id: str,
    books: list[Book],
    delay_seconds: float,
    query: str,
    scenario: str | None,
) -> list[Book]:
    """Search one dummy bookstore.

    Args:
        site_id: Dummy bookstore ID.
        books: Books owned by the dummy bookstore.
        delay_seconds: Artificial response delay.
        query: Normalized search query.
        scenario: Optional scenario name for manual verification.

    Returns:
        Matched books.

    Raises:
        RuntimeError: Raised when an error scenario is requested.
    """

    if scenario == f"{site_id}_timeout":
        await asyncio.sleep(SITE_TIMEOUT_SECONDS + 1.0)

    await asyncio.sleep(delay_seconds)

    if scenario == f"{site_id}_error":
        raise RuntimeError("dummy site error")

    return [
        book
        for book in books
        if query in book["title"].lower() or query in book["author"].lower()
    ]


def normalize_query(value: str | None) -> str:
    """Normalize user search query.

    Args:
        value: Raw query value.

    Returns:
        Trimmed and lower-cased query.
    """

    if value is None:
        return ""
    return value.strip().lower()


def build_site_error(site_id: str, site_name: str, message: str) -> SiteResult:
    """Build a site-level error result.

    Args:
        site_id: Dummy bookstore ID.
        site_name: Dummy bookstore display name.
        message: Error reason.

    Returns:
        Site-level error result.
    """

    return {
        "site_id": site_id,
        "site_name": site_name,
        "status": "error",
        "result_count": 0,
        "results": [],
        "error": message,
    }


def build_response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    """Build an HTTP response.

    Args:
        status_code: HTTP status code.
        body: JSON serializable response body.

    Returns:
        Lambda Function URL response.
    """

    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json; charset=utf-8",
        },
        "body": json.dumps(body, ensure_ascii=False),
    }

"""Dummy book data for pseudo scraping."""

from typing import TypedDict


class Book(TypedDict):
    """Book item returned by a dummy bookstore."""

    id: str
    title: str
    author: str
    price: int
    currency: str
    availability: str
    site_id: str
    site_name: str
    url: str


BOOK_MARKET_BOOKS: list[Book] = [
    {
        "id": "book-market-001",
        "title": "Terraform入門",
        "author": "山田太郎",
        "price": 1800,
        "currency": "JPY",
        "availability": "in_stock",
        "site_id": "book_market",
        "site_name": "Book Market",
        "url": "https://example.com/book-market/001",
    },
    {
        "id": "book-market-002",
        "title": "AWSサーバレス設計ガイド",
        "author": "佐藤花子",
        "price": 2400,
        "currency": "JPY",
        "availability": "low_stock",
        "site_id": "book_market",
        "site_name": "Book Market",
        "url": "https://example.com/book-market/002",
    },
    {
        "id": "book-market-003",
        "title": "Python非同期プログラミング",
        "author": "鈴木一郎",
        "price": 2100,
        "currency": "JPY",
        "availability": "out_of_stock",
        "site_id": "book_market",
        "site_name": "Book Market",
        "url": "https://example.com/book-market/003",
    },
]

OLD_BOOKS_ONLINE_BOOKS: list[Book] = [
    {
        "id": "old-books-online-001",
        "title": "実践Terraform運用",
        "author": "山田太郎",
        "price": 3200,
        "currency": "JPY",
        "availability": "low_stock",
        "site_id": "old_books_online",
        "site_name": "Old Books Online",
        "url": "https://example.com/old-books-online/001",
    },
    {
        "id": "old-books-online-003",
        "title": "Terraform入門",
        "author": "山田太郎",
        "price": 2200,
        "currency": "JPY",
        "availability": "low_stock",
        "site_id": "old_books_online",
        "site_name": "Old Books Online",
        "url": "https://example.com/old-books-online/003",
    },
    {
        "id": "old-books-online-004",
        "title": "AWSサーバレス設計ガイド",
        "author": "佐藤花子",
        "price": 2800,
        "currency": "JPY",
        "availability": "in_stock",
        "site_id": "old_books_online",
        "site_name": "Old Books Online",
        "url": "https://example.com/old-books-online/004",
    },
    {
        "id": "old-books-online-002",
        "title": "クラウドインフラ設計の基礎",
        "author": "高橋次郎",
        "price": 1500,
        "currency": "JPY",
        "availability": "in_stock",
        "site_id": "old_books_online",
        "site_name": "Old Books Online",
        "url": "https://example.com/old-books-online/002",
    },
]

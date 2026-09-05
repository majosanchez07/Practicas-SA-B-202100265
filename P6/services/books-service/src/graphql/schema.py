import strawberry
from typing import List, Optional
from sqlalchemy.orm import Session
from src.models.database import SessionLocal
from src.models.book import Book

@strawberry.type
class BookType:
    id: int
    title: str
    author: str
    isbn: str
    genre: Optional[str]
    available: bool

@strawberry.type
class Query:
    @strawberry.field
    def books(self) -> List[BookType]:
        db: Session = SessionLocal()
        try:
            books = db.query(Book).all()
            return [BookType(id=b.id, title=b.title, author=b.author,
                           isbn=b.isbn, genre=b.genre, available=b.available)
                    for b in books]
        finally:
            db.close()

    @strawberry.field
    def book(self, id: int) -> Optional[BookType]:
        db: Session = SessionLocal()
        try:
            b = db.query(Book).filter(Book.id == id).first()
            if not b:
                return None
            return BookType(id=b.id, title=b.title, author=b.author,
                          isbn=b.isbn, genre=b.genre, available=b.available)
        finally:
            db.close()

@strawberry.type
class Mutation:
    @strawberry.mutation
    def create_book(self, title: str, author: str, isbn: str,
                    genre: Optional[str] = None) -> BookType:
        db: Session = SessionLocal()
        try:
            book = Book(title=title, author=author, isbn=isbn, genre=genre)
            db.add(book)
            db.commit()
            db.refresh(book)
            return BookType(id=book.id, title=book.title, author=book.author,
                          isbn=book.isbn, genre=book.genre, available=book.available)
        finally:
            db.close()

    @strawberry.mutation
    def update_book_availability(self, id: int, available: bool) -> Optional[BookType]:
        db: Session = SessionLocal()
        try:
            book = db.query(Book).filter(Book.id == id).first()
            if not book:
                return None
            book.available = available
            db.commit()
            db.refresh(book)
            return BookType(id=book.id, title=book.title, author=book.author,
                          isbn=book.isbn, genre=book.genre, available=book.available)
        finally:
            db.close()

schema = strawberry.Schema(query=Query, mutation=Mutation)

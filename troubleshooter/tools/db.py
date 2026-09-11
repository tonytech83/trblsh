from collections.abc import Generator

from agents import function_tool
from sqlmodel import Session, SQLModel, create_engine

DATABASE_URL = "sqlite:///db.db"

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})


def init_db() -> None:
    # Import models so SQLModel.metadata is populated before create_all
    import models.incident  # noqa: F401

    SQLModel.metadata.create_all(engine)


@function_tool
def get_session() -> Generator[Session, None, None]:
    """Open the session to database"""
    with Session(engine) as session:
        yield session

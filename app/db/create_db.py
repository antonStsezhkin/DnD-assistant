from pathlib import Path
import sqlite3


def get_project_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "requirements.txt").exists():
            return parent
    return Path(__file__).resolve().parent


ROOT_DIR = get_project_root()
SCHEMA_FILE = Path(__file__).resolve().parent / "schema.sql"
DB_PATH = ROOT_DIR / "dnd.db"


def create_database(db_path: Path = DB_PATH) -> None:
    schema = SCHEMA_FILE.read_text(encoding="utf-8")
    conn = sqlite3.connect(db_path)
    try:
        conn.executescript(schema)
        conn.commit()
        print(f"Database created: {db_path}")
    finally:
        conn.close()


if __name__ == "__main__":
    create_database()

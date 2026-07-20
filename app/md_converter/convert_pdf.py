from pathlib import Path
import pymupdf4llm


def convert_pdf(file_path: Path, book_dir: Path) -> str:
    # book_dir уже содержит санитизированное имя; images/ — вложенная папка
    image_dir = book_dir / "images"
    image_dir.mkdir(parents=True, exist_ok=True)

    return pymupdf4llm.to_markdown(
        str(file_path),
        force_text=True,
        write_images=True,
        image_path=str(image_dir),
    )

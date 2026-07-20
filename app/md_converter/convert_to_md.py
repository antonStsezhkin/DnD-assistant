from pathlib import Path

from convert_pdf import convert_pdf
from convert_word import convert_word
from convert_excel import convert_excel
from splitter import split_and_write


def get_project_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "requirements.txt").exists():
            return parent
    return Path(__file__).resolve().parent


ROOT_DIR = get_project_root()
INPUT_DIR = ROOT_DIR / "data_source"
OUTPUT_DIR = ROOT_DIR / "rulebooks"

if not INPUT_DIR.exists():
    raise FileNotFoundError(
        f"\n[КРИТИЧЕСКАЯ ОШИБКА] Папка с исходными файлами не найдена!\n"
        f"Ожидалось тут: {INPUT_DIR}\n"
        f"Пожалуйста, создайте её вручную и положите туда файлы."
    )

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

_PDF_EXTS = {".pdf"}
_WORD_EXTS = {".docx", ".doc"}
_EXCEL_EXTS = {".xlsx", ".xls", ".csv"}
_TEXT_EXTS = {".txt"}


def convert_files_to_markdown():
    for file_path in INPUT_DIR.iterdir():
        if file_path.is_dir():
            continue

        ext = file_path.suffix.lower()
        if ext not in _PDF_EXTS | _WORD_EXTS | _EXCEL_EXTS | _TEXT_EXTS:
            continue

        # Пробелы → подчёркивания: pymupdf4llm санитизирует image_path таким же образом
        safe_stem = file_path.stem.replace(' ', '_')
        book_dir = OUTPUT_DIR / safe_stem
        if book_dir.exists():
            continue

        print(f"Converting {file_path.name}...")
        try:
            if ext in _PDF_EXTS:
                md_text = convert_pdf(file_path, book_dir)
                split_and_write(md_text, source_name=safe_stem, output_dir=book_dir)

            elif ext in _WORD_EXTS:
                md_text = convert_word(file_path)
                split_and_write(md_text, source_name=safe_stem, output_dir=book_dir)

            elif ext in _TEXT_EXTS:
                text = file_path.read_text(encoding="utf-8")
                split_and_write(text, source_name=safe_stem, output_dir=book_dir, content_type="text")

            else:  # Excel / CSV
                for sheet_name, csv_text in convert_excel(file_path):
                    if sheet_name is None:
                        # CSV — чанки прямо в папке книги
                        target_dir = book_dir
                        src_name = file_path.stem
                    else:
                        # Excel — каждый лист в своей подпапке
                        target_dir = book_dir / sheet_name
                        src_name = f"{file_path.stem} ({sheet_name})"
                    split_and_write(csv_text, source_name=src_name, output_dir=target_dir, content_type="csv")

        except Exception as e:
            print(f"Error processing {file_path.name}: {e}")


if __name__ == "__main__":
    convert_files_to_markdown()
    print("All conversions complete!")

from pathlib import Path
import docx2txt


def convert_word(file_path: Path) -> str:
    return f"# {file_path.stem}\n\n{docx2txt.process(str(file_path))}"

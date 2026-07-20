import io
from pathlib import Path

import pandas as pd


def convert_excel(file_path: Path) -> list[tuple[str | None, str]]:
    """
    Returns a list of (sheet_name, csv_string) pairs.
    CSV files return a single entry with sheet_name=None (no subdirectory).
    Excel files return one entry per sheet.
    """
    ext = file_path.suffix.lower()

    if ext == ".csv":
        df = pd.read_csv(str(file_path))
        buf = io.StringIO()
        df.to_csv(buf, index=False)
        return [(None, buf.getvalue())]

    xl = pd.ExcelFile(str(file_path))
    result = []
    for sheet_name in xl.sheet_names:
        df = xl.parse(sheet_name)
        buf = io.StringIO()
        df.to_csv(buf, index=False)
        result.append((str(sheet_name), buf.getvalue()))
    return result

import csv
import io
import re
from pathlib import Path

# ~4 chars per token; target 2048 tokens to leave room for prompt + query
_CHUNK_CHARS = 2048 * 4


def _slugify(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r'[^\w\s]', '', text)
    text = re.sub(r'\s+', '_', text)
    return text[:60]


def _write_chunks(chunks: list[tuple[str, str]], source_name: str, output_dir: Path) -> None:
    """Writes (title, body) pairs as numbered slug files with YAML frontmatter."""
    output_dir.mkdir(parents=True, exist_ok=True)
    used: set[str] = set()
    for idx, (title, body) in enumerate(chunks):
        base = f"{idx:02d}_{_slugify(title)}"
        name = base
        counter = 1
        while name in used:
            name = f"{base}_{counter}"
            counter += 1
        used.add(name)
        frontmatter = f"---\nsource: {source_name}\nchapter: {title}\n---\n\n"
        (output_dir / f"{name}.md").write_text(frontmatter + body, encoding="utf-8")


def _md_table(header: list[str], rows: list[list[str]]) -> str:
    def esc(v: str) -> str:
        return str(v).replace("|", "\\|").replace("\n", " ")

    lines = [
        "| " + " | ".join(esc(h) for h in header) + " |",
        "| " + " | ".join("---" for _ in header) + " |",
    ]
    for row in rows:
        padded = list(row) + [""] * max(0, len(header) - len(row))
        lines.append("| " + " | ".join(esc(c) for c in padded[:len(header)]) + " |")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Public split functions
# ---------------------------------------------------------------------------

def split_markdown(md_text: str, source_name: str, output_dir: Path) -> None:
    parts = re.split(r'^(## .+)$', md_text, flags=re.MULTILINE)
    chunks: list[tuple[str, str]] = []

    preamble = parts[0].strip()
    if preamble:
        chunks.append(("Preamble", preamble))

    for i in range(1, len(parts), 2):
        heading = parts[i]
        body = parts[i + 1] if i + 1 < len(parts) else ""
        title = heading[3:].strip()
        chunks.append((title, f"{heading}{body.rstrip()}"))

    _write_chunks(chunks, source_name, output_dir)


def split_csv(csv_text: str, source_name: str, output_dir: Path) -> None:
    reader = csv.reader(io.StringIO(csv_text))
    rows = list(reader)
    if not rows:
        return

    header = rows[0]
    data = rows[1:]

    # Группируем строки по символьному бюджету; каждый чанк включает заголовок
    groups: list[list[list[str]]] = []
    current: list[list[str]] = []
    current_chars = 0

    for row in data:
        row_chars = sum(len(str(c)) for c in row) + len(row) * 3
        if current_chars + row_chars > _CHUNK_CHARS and current:
            groups.append(current)
            current = [row]
            current_chars = row_chars
        else:
            current.append(row)
            current_chars += row_chars
    if current:
        groups.append(current)

    chunks: list[tuple[str, str]] = []
    offset = 1
    for group in groups:
        title = f"rows {offset}–{offset + len(group) - 1}"
        chunks.append((title, _md_table(header, group)))
        offset += len(group)

    _write_chunks(chunks, source_name, output_dir)


def split_text(text: str, source_name: str, output_dir: Path) -> None:
    paragraphs = re.split(r'\n{2,}', text.strip())
    groups: list[list[str]] = []
    current: list[str] = []
    current_chars = 0

    for para in paragraphs:
        if current_chars + len(para) > _CHUNK_CHARS and current:
            groups.append(current)
            current = [para]
            current_chars = len(para)
        else:
            current.append(para)
            current_chars += len(para)
    if current:
        groups.append(current)

    chunks = [(f"part {idx + 1}", "\n\n".join(group)) for idx, group in enumerate(groups)]
    _write_chunks(chunks, source_name, output_dir)


def split_and_write(
    content: str,
    source_name: str,
    output_dir: Path,
    content_type: str = "markdown",
) -> None:
    if content_type == "markdown":
        split_markdown(content, source_name, output_dir)
    elif content_type == "csv":
        split_csv(content, source_name, output_dir)
    elif content_type == "text":
        split_text(content, source_name, output_dir)
    else:
        raise ValueError(f"Unknown content_type: {content_type!r}")

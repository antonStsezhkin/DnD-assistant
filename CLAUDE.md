# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

A tabletop RPG assistant. Long-term goal: convert rulebooks into LLM-friendly wikis that can be used to generate custom rulebooks and campaign extensions. Currently in early development — only the document ingestion pipeline is implemented.

## Setup

```bash
# Create and activate virtual environment (Python 3.12)
python -m venv .venv
.venv/Scripts/activate  # Windows

pip install -r requirements.txt
```

## Running the Converter

```bash
python app/md_converter/convert_to_md.py
```

Converts all files in `data_source/` into per-rulebook chapter wikis under `rulebooks/`. Each source file becomes a subdirectory; each `##` heading becomes a separate `.md` file with YAML frontmatter (`source`, `chapter`). Already-converted books are skipped (idempotent). To re-convert, delete the corresponding subdirectory from `rulebooks/`.

## Architecture

The pipeline ingests rulebooks (PDF, DOCX, XLSX/CSV), converts them to Markdown, splits by chapter, and writes LLM-sized chunks with source metadata — one subdirectory per rulebook.

**`app/md_converter/convert_to_md.py`** — orchestrator. Walks `data_source/`, dispatches by extension, calls `split_and_write`. Detects project root via `requirements.txt` marker.

**`app/md_converter/convert_pdf.py`** — PDF via `pymupdf4llm` (`force_text=True, write_images=True`). Images saved to `rulebooks/<stem>/images/`.

**`app/md_converter/convert_word.py`** — Word via `docx2txt`.

**`app/md_converter/convert_excel.py`** — Excel/CSV via `pandas`.

**`app/md_converter/split_md.py`** — splits a markdown string on `##` headings. Writes `{index:02d}_{slug}.md` files with YAML frontmatter (`source`, `chapter`). Collision-safe within and across rulebooks.

**`data_source/`** — source documents. Two PDFs present: English starter rulebook and Russian 5e Player's Handbook (41 MB).

**`rulebooks/`** — output directory, gitignored by convention, auto-created on first run. Structure: `rulebooks/<stem>/<chapter>.md`.

## Notes

- Comments in the codebase are written in Russian.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

from pathlib import Path
import pymupdf4llm
import docx2txt
import pandas as pd


# 1. Получаем корень проекта через маркер (requirements.txt) - это спасет от путаницы с ../
def get_project_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "requirements.txt").exists():
            return parent
    return Path(__file__).resolve().parent


ROOT_DIR = get_project_root()
INPUT_DIR = ROOT_DIR / "data_source"
OUTPUT_DIR = ROOT_DIR / "md"

# Защита: сообщаем, если папки с исходными файлами нет на диске
if not INPUT_DIR.exists():
    raise FileNotFoundError(
        f"\n[КРИТИЧЕСКАЯ ОШИБКА] Папка с исходными файлами не найдена!\n"
        f"Ожидалось тут: {INPUT_DIR}\n"
        f"Пожалуйста, создайте её вручную и положите туда файлы."
    )

# Создаем папку для markdown, если её нет
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def convert_files_to_markdown():
    # .iterdir() заменяет os.listdir() и сразу возвращает объекты Path
    for file_path in INPUT_DIR.iterdir():
        if file_path.is_dir():
            continue  # Пропускаем подпапки, если они есть

        filename = file_path.name
        base_name = file_path.stem  # Имя без расширения (заменяет os.path.splitext)
        ext = file_path.suffix.lower()  # Расширение с точкой (например, '.pdf')

        output_file = OUTPUT_DIR / f"{base_name}.md"

        # Пропуск уже обработанных
        if output_file.exists():
            continue

        print(f"Converting {filename}...")
        try:
            if ext == '.pdf':
                md_text = pymupdf4llm.to_markdown(str(file_path), force_text=True, write_images=False)

            elif ext in ['.docx', '.doc']:
                md_text = f"# {base_name}\n\n{docx2txt.process(str(file_path))}"

            elif ext in ['.xlsx', '.xls', '.csv']:
                # Использование str(file_path) гарантирует совместимость со старыми версиями pandas
                df = pd.read_excel(str(file_path)) if ext != '.csv' else pd.read_csv(str(file_path))
                md_text = f"# {base_name}\n\n{df.to_markdown(index=False)}"

            else:
                continue  # Пропускаем неподдерживаемые форматы

            # Запись файла через pathlib (.write_text) автоматически открывает и закрывает файл
            output_file.write_text(md_text, encoding="utf-8")

        except Exception as e:
            print(f"Error processing {filename}: {e}")


if __name__ == "__main__":
    convert_files_to_markdown()
    print("All conversions complete!")

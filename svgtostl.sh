#!/bin/bash

# Проверяем наличие первого обязательного аргумента
if [ -z "$1" ]; then
    echo "Ошибка: Не указан входной файл SVG."
    echo "Использование: $0 <путь_к_файлу.svg> [высота мм]"
    exit 1
fi

INPUT_FILE=$(realpath "$1")
if [ ! -f "$INPUT_FILE" ]; then
    echo "Ошибка: Файл '$INPUT_FILE' не найден."
    exit 1
fi

# Если второй аргумент пустой, выставляем стандартные 1.6 мм
PCB_HEIGHT_MM="${2:-0.15}"

# Генерируем имя выходного файла STL в той же директории
OUTPUT_DIR=$(dirname "$INPUT_FILE")
OUTPUT_NAME=$(basename "${INPUT_FILE%.*}.stl")
OUTPUT_FILE="$OUTPUT_DIR/$OUTPUT_NAME"

# ==============================================================================
# ШАГ 1: ЭКСТРУЗИЯ SVG В STL (ЧЕРЕЗ OPENSCAD CLI)
# ==============================================================================

echo "--> Шаг 1: Экструзия SVG контура в 3D модель STL ($PCB_HEIGHT_MM мм)..."
echo "Вход:  $INPUT_FILE"
echo "Выход: $OUTPUT_FILE"

# Передаем команду экструзии через echo в stdin OpenSCAD (обозначается как -)
# QT_QPA_PLATFORM=offscreen гарантирует 100% headless режим без GUI зависимостей
QT_QPA_PLATFORM=offscreen openscad -o "$OUTPUT_FILE" - <<EOF
linear_extrude(height=$PCB_HEIGHT_MM) import("$INPUT_FILE");
EOF

# Проверка создания STL
if [ -f "$OUTPUT_FILE" ]; then
    echo "=================================================="
    echo "   УСПЕХ! 3D-модель изоляционного контура готова."
    echo "   STL файл сохранен: $OUTPUT_FILE"
    echo "=================================================="
else
    echo "Ошибка генерации STL в OpenSCAD."
    exit 1
fi
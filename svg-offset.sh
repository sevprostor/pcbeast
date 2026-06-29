#!/bin/bash

# Проверяем наличие первого обязательного аргумента
if [ -z "$1" ]; then
    echo "Ошибка: Не указан входной файл SVG."
    echo "Использование: $0 <путь_к_файлу.svg> [припуск в мм]"
    exit 1
fi

INPUT_FILE=$(realpath "$1")
if [ ! -f "$INPUT_FILE" ]; then
    echo "Ошибка: Файл '$INPUT_FILE' не найден."
    exit 1
fi

OFFSET_MM="${2:-0}"
OUTPUT_FILE="${INPUT_FILE%.*}_poly_offset.svg"

echo "=================================================="
echo "    Калибровка масштаба и точный оффсет платы"
echo "=================================================="
echo "Входной файл:  $INPUT_FILE"

# ------------------------------------------------------------------------------
# АВТОМАТИЧЕСКИЙ РАСЧЕТ МАСШТАБА (ПИКСЕЛИ -> ММ)
# ------------------------------------------------------------------------------
# Извлекаем ширину холста в мм и в пикселях из тега <svg>, чтобы найти точный шаг
SVG_WIDTH_MM=$(grep -oE 'width="[0-9.]+(mm)?' "$INPUT_FILE" | head -n 1 | tr -d 'width="m')
VIEWBOX_WIDTH=$(grep -oE 'viewBox="[0-9.-]+ [0-9.-]+ [0-9.]+' "$INPUT_FILE" | head -n 1 | awk '{print $3}')

# Если CAD-система не прописала ширину в явных мм, используем стандартный шаг Inkscape (96 DPI)
if [ -z "$SVG_WIDTH_MM" ] || [ -z "$VIEWBOX_WIDTH" ]; then
    # Дефолтный коэффициент: 1 мм = 3.779527 px
    PX_PER_MM="3.779527"
    echo "--> Предупреждение: Масштаб не найден в файле. Используем дефолтные 96 DPI."
else
    # Вычисляем сколько пикселей viewBox содержится в одном физическом миллиметре платы
    PX_PER_MM=$(echo "scale=6; $VIEWBOX_WIDTH / $SVG_WIDTH_MM" | bc)
    echo "--> Обнаружен масштаб документа: 1 мм = $PX_PER_MM px (viewBox)"
fi

# ------------------------------------------------------------------------------
# ВЫЧИСЛЕНИЕ ТОЧНОЙ ТОЛЩИНЫ ОБВОДКИ
# ------------------------------------------------------------------------------
ACTIONS="select-all;object-stroke-to-path;path-union;selection-ungroup;select-all;path-union"

IS_OFFSET_POSITIVE=$(echo "$OFFSET_MM > 0" | bc -l)

if [ "$IS_OFFSET_POSITIVE" -eq 1 ]; then
    # Обводка идет в обе стороны, умножаем припуск на 2
    STROKE_WIDTH_MM=$(echo "scale=4; $OFFSET_MM * 2" | bc)
    
    # Переводим миллиметры в точные пиксели внутреннего масштаба вашего файла
    STROKE_WIDTH_PX=$(echo "scale=4; $STROKE_WIDTH_MM * $PX_PER_MM" | bc)
    
    echo "Припуск:       +$OFFSET_MM мм"
    echo "Толщина линии: $STROKE_WIDTH_PX px (масштабировано)"
    echo "--------------------------------------------------"
    echo "--> Наращивание точной геометрии..."
    
    # Передаем Inkscape значение СТРОГО в пикселях (px), адаптированных под ваш viewBox
    ACTIONS="$ACTIONS;select-all;object-set-property:stroke,#000000;object-set-property:stroke-width,${STROKE_WIDTH_PX}px;object-set-property:stroke-linejoin,round;object-stroke-to-path;selection-ungroup;select-all;path-union"
else
    echo "Припуск:       0 мм (только слияние)"
    echo "--------------------------------------------------"
fi

ACTIONS="$ACTIONS;export-filename:$OUTPUT_FILE;export-do"

echo "--> Запуск векторного конвейера..."
inkscape "$INPUT_FILE" --actions="$ACTIONS"

if [ -f "$OUTPUT_FILE" ]; then
    echo "--> Готово! Точный размер припуска сформирован."
    echo "=================================================="
    exit 0
else
    echo "Ошибка обработки."
    exit 1
fi
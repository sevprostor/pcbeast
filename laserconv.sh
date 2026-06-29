#!/bin/bash

# ==============================================================================
# НАСТРОЙКА: Максимальная мощность лазера во FluidNC (параметр $30)
# ==============================================================================
LASER_MAX_POWER=1000

# Проверяем, передан ли файл G-кода в качестве аргумента
if [ -z "$1" ]; then
    echo "Ошибка: Не указан входной файл G-кода."
    echo "Использование: $0 <путь_к_файлу.gcode>"
    exit 1
fi

INPUT_FILE="$1"

# Проверяем, существует ли указанный файл
if [ ! -f "$INPUT_FILE" ]; then
    echo "Ошибка: Файл '$INPUT_FILE' не найден."
    exit 1
fi

# Формируем имена для временного и выходного файлов
CLEANED_TEMP="${INPUT_FILE%.*}_no_wipe.tmp"
OUTPUT_FILE="${INPUT_FILE%.*}_laser.gcode"

> "$OUTPUT_FILE"

echo "=================================================="
echo " Starting G-code Conversion for FluidNC"
echo "=================================================="
echo "Входной файл:  $INPUT_FILE"

# ------------------------------------------------------------------------------
# ШАГ 1: ТОТАЛЬНОЕ УДАЛЕНИЕ БЛОКОВ WIPE ИЗ ВСЕГО ТЕКСТА
# ------------------------------------------------------------------------------
echo "--> Шаг 1: Поиск и удаление всех блоков ;WIPE_START ... ;WIPE_END..."

# Команда sed удаляет всё, что находится между указанными маркерами включительно
sed '/;WIPE_START/,/;WIPE_END/d' "$INPUT_FILE" > "$CLEANED_TEMP"

# Подсчитываем строки в очищенном файле для индикатора прогресса
TOTAL_LINES=$(wc -l < "$CLEANED_TEMP")
echo "--> Блоки очистки сопла успешно вырезаны."
echo "--> Строк для финальной обработки: $TOTAL_LINES"
echo "--------------------------------------------------"
echo "--> Шаг 2: Конвертация координат и команд лазера..."

# Записываем чистую лазерную инициализацию во FluidNC
echo "G21 ; Режим миллиметров" >> "$OUTPUT_FILE"
echo "G90 ; Абсолютные координаты" >> "$OUTPUT_FILE"
echo "M3  ; Включение лазера" >> "$OUTPUT_FILE"

# Флаги и счетчики
HAS_SET_Z=0
CURRENT_LINE=0

# ------------------------------------------------------------------------------
# ШАГ 2: ПОСТРОЧНАЯ ОБРАБОТКА ОЧИЩЕННОГО ФАЙЛА
# ------------------------------------------------------------------------------
while IFS= read -r line || [ -n "$line" ]; do
    ((CURRENT_LINE++))
    
    # Выводим прогресс каждые 5000 строк
    if (( CURRENT_LINE % 500 == 0 )); then
        PERCENT=$(( CURRENT_LINE * 100 / TOTAL_LINES ))
        echo "    Обработано строк: $CURRENT_LINE из $TOTAL_LINES ($PERCENT%)"
    fi

    # Удаляем пробелы по краям строки
    line_trimmed=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Игнорируем пустые строки и комментарии слайсера
    if [ -z "$line_trimmed" ] || [[ "$line_trimmed" == \;* ]]; then
        continue
    fi

    # Очищаем строку от комментариев в конце кода
    line_clean=$(echo "$line_trimmed" | sed 's/;.*//' | sed 's/[[:space:]]*$//')
    
    # Выделяем саму команду (первое слово)
    first_cmd=$(echo "$line_clean" | awk '{print $1}')

    # ЖЕСТКАЯ ФИЛЬТРАЦИЯ: Разрешаем только команды перемещения G0 и G1
    if [ "$first_cmd" != "G0" ] && [ "$first_cmd" != "G1" ]; then
        continue
    fi

    # Обработка параметра выдавливания (E)
    if [[ "$line_clean" =~ E[-+]?[0-9]*\.?[0-9]+ ]]; then
        # Есть E -> рабочий ход. Меняем E на S[MAX_POWER]
        line_no_printer=$(echo "$line_clean" | sed -E 's/E[-+]?[0-9]*\.?[0-9]+//g')
        if [[ ! "$line_no_printer" =~ S[0-9]+ ]]; then
            line_no_printer="$line_no_printer S$LASER_MAX_POWER"
        fi
    else
        # Нет E -> холостой переход. Принудительно гасим лазер (S0)
        line_no_printer="$line_clean"
        if [[ ! "$line_no_printer" =~ S[0-9]+ ]]; then
            line_no_printer="$line_no_printer S0"
        fi
    fi

    # Обработка оси Z (Высота фокуса)
    if [[ "$line_no_printer" =~ Z[-+]?[0-9]*\.?[0-9]+ ]]; then
        if [ "$HAS_SET_Z" -eq 0 ]; then
            HAS_SET_Z=1  # Оставляем только первый Z (начальный фокус)
        else
            line_no_printer=$(echo "$line_no_printer" | sed -E 's/Z[-+]?[0-9]*\.?[0-9]+//g')
        fi
    fi

    # Форматирование пробелов для FluidNC
    fixed_spaces=$(echo "$line_no_printer" | sed -E 's/([GMXYZFS])/ \1/g' | sed -E 's/[[:space:]]+/ /g' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Проверка, чтобы в файл не записалась пустая одинокая команда (например, если строка содержала только удаленный параметр E)
    clean_cmd_check=$(echo "$fixed_spaces" | awk '{print $2}')
    if [ -n "$clean_cmd_check" ]; then
        echo "$fixed_spaces" >> "$OUTPUT_FILE"
    fi

done < "$CLEANED_TEMP"

# Удаляем временный файл за собой
rm -f "$CLEANED_TEMP"

# 3. ФИНАЛЬНОЕ ЗАКРЫТИЕ ПРОГРАММЫ
echo "M5 ; Выключить лазер" >> "$OUTPUT_FILE"
echo "M2 ; Конец программы" >> "$OUTPUT_FILE"

echo "--------------------------------------------------"
echo " Конвертация успешно завершена на 100%!"
echo " Результат записан в: $OUTPUT_FILE"
echo "=================================================="
exit 0
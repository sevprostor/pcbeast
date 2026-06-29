#!/bin/bash

# ==============================================================================
# НАСТРОЙКА: Максимальная мощность лазера во FluidNC (параметр $30)
# ==============================================================================
#LASER_MAX_POWER=1000
FEED_RAPID=10000

# Проверяем, передан ли файл G-кода в качестве аргумента
if [ -z "$1" ]; then
    echo "Ошибка: Не указан входной файл G-кода."
    echo "Использование: $0 <путь_к_файлу.gcode> <подача мм/с> <мощность лазера>"
    exit 1
fi

INPUT_FILE="$1"
#FEED_WORK="$2"
LASER_MAX_POWER="${3:-1000}"
FEED_WORK="${2:-3000}"


# Проверяем, существует ли указанный файл
if [ ! -f "$INPUT_FILE" ]; then
    echo "Ошибка: Файл '$INPUT_FILE' не найден."
    exit 1
fi

echo "--------------------------------------------------"
echo "Подача: $FEED_WORK, шпиндель: $LASER_MAX_POWER"
echo "--------------------------------------------------"

# Формируем имена для временного и выходного файлов
CLEANED_TEMP="${INPUT_FILE%.*}_no_wipe.tmp"
OUTPUT_FILE="${INPUT_FILE%.*}_laser.gcode"

> "$OUTPUT_FILE"

echo "=================================================="
echo " Starting G-code Conversion for FluidNC"
echo "=================================================="
echo "Входной файл:  $INPUT_FILE"
echo "Подача: $FEED_WORK/$FEED_RAPID"

# === НОВЫЕ ПАРАМЕТРЫ ПОДАЧИ ===
# Убедитесь, что эти переменные передаются в скрипт или заданы выше
#FEED_WORK=${FEED_WORK:-1200}   # Скорость рабочей подачи (по умолчанию 1200)
#FEED_RAPID=${FEED_RAPID:-3000} # Скорость холостого хода (по умолчанию 3000)



# ------------------------------------------------------------------------------
# ШАГ 1: ТОТАЛЬНОЕ УДАЛЕНИЕ БЛОКОВ WIPE ИЗ ВСЕГО ТЕКСТА
# ------------------------------------------------------------------------------
echo "--> Шаг 1: Поиск и удаление всех блоков ;WIPE_START ... ;WIPE_END..."

sed '/;WIPE_START/,/;WIPE_END/d' "$INPUT_FILE" > "$CLEANED_TEMP"

TOTAL_LINES=$(wc -l < "$CLEANED_TEMP")
echo "--> Блоки очистки сопла успешно вырезаны."
echo "--> Строк для финальной обработки: $TOTAL_LINES"
echo "--------------------------------------------------"
echo "--> Шаг 2: Конвертация координат и команд лазера..."

# Записываем чистую лазерную инициализацию во FluidNC
echo "G21 ; Режим миллиметров" >> "$OUTPUT_FILE"
echo "G90 ; Абсолютные координаты" >> "$OUTPUT_FILE"
echo "M3  ; Включение лазера" >> "$OUTPUT_FILE"
# Установка начальной рабочей подачи в начале программы
echo "F$FEED_WORK ; Установка начальной рабочей скорости" >> "$OUTPUT_FILE"

# Флаги и счетчики
HAS_SET_Z=0
CURRENT_LINE=0
LAST_FEED_MODE="" # Запоминаем последний режим ("WORK" или "RAPID")

# ------------------------------------------------------------------------------
# ШАГ 2: ПОСТРОЧНАЯ ОБРАБОТКА ОЧИЩЕННОГО ФАЙЛА
# ------------------------------------------------------------------------------
while IFS= read -r line || [ -n "$line" ]; do
    ((CURRENT_LINE++))
    
    if (( CURRENT_LINE % 100 == 0 )); then
        PERCENT=$(( CURRENT_LINE * 100 / TOTAL_LINES ))
        echo "XXX"
        echo "$PERCENT"  # Новое значение шкалы в процентах (от 0 до 100)
        echo "Конвертация Klipper > FluidNC, обработано $CURRENT_LINE строк из $TOTAL_LINES..." # Текст, который отобразится в окошке
        echo "XXX"
        #echo "    Обработано строк: $CURRENT_LINE из $TOTAL_LINES ($PERCENT%)"
    fi

    line_trimmed=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [ -z "$line_trimmed" ] || [[ "$line_trimmed" == \;* ]]; then
        continue
    fi

    line_clean=$(echo "$line_trimmed" | sed 's/;.*//' | sed 's/[[:space:]]*$//')
    
    first_cmd=$(echo "$line_clean" | awk '{print $1}')

    if [ "$first_cmd" != "G0" ] && [ "$first_cmd" != "G1" ]; then
        continue
    fi

    # Удаляем старый параметр скорости F, если он есть в строке, 
    # чтобы он не конфликтовал с нашими новыми настройками
    line_clean=$(echo "$line_clean" | sed -E 's/F[0-9]*\.?[0-9]+//g')

    # Обработка параметра выдавливания (E) и логики скоростей
    if [[ "$line_clean" =~ E[-+]?[0-9]*\.?[0-9]+ ]]; then
        # === РАБОЧИЙ ХОД (Есть экструзия E) ===
        line_no_printer=$(echo "$line_clean" | sed -E 's/E[-+]?[0-9]*\.?[0-9]+//g')
        
        if [[ ! "$line_no_printer" =~ S[0-9]+ ]]; then
            line_no_printer="$line_no_printer S$LASER_MAX_POWER"
        fi

        # Если до этого был холостой ход, принудительно возвращаем рабочую скорость
        if [ "$LAST_FEED_MODE" != "WORK" ]; then
            line_no_printer="$line_no_printer F$FEED_WORK"
            LAST_FEED_MODE="WORK"
        fi
    else
        # === ХОЛОСТОЙ ХОД (Нет экструзии E) ===
        line_no_printer="$line_clean"
        
        if [[ ! "$line_no_printer" =~ S[0-9]+ ]]; then
            line_no_printer="$line_no_printer S0"
        fi

        # Если до этого был рабочий ход, принудительно включаем скорость холостого хода
        if [ "$LAST_FEED_MODE" != "RAPID" ]; then
            line_no_printer="$line_no_printer F$FEED_RAPID"
            LAST_FEED_MODE="RAPID"
        fi
    fi

    # Обработка оси Z (Высота фокуса)
    if [[ "$line_no_printer" =~ Z[-+]?[0-9]*\.?[0-9]+ ]]; then
        if [ "$HAS_SET_Z" -eq 0 ]; then
            HAS_SET_Z=1  
        else
            line_no_printer=$(echo "$line_no_printer" | sed -E 's/Z[-+]?[0-9]*\.?[0-9]+//g')
        fi
    fi

    # Форматирование пробелов для FluidNC
    fixed_spaces=$(echo "$line_no_printer" | sed -E 's/([GMXYZFS])/ \1/g' | sed -E 's/[[:space:]]+/ /g' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    clean_cmd_check=$(echo "$fixed_spaces" | awk '{print $2}')
    if [ -n "$clean_cmd_check" ]; then
        echo "$fixed_spaces" >> "$OUTPUT_FILE"
    fi

done < "$CLEANED_TEMP"

rm -f "$CLEANED_TEMP"

# 3. ФИНАЛЬНОЕ ЗАКРЫТИЕ ПРОГРАММЫ
echo "M5 ; Выключить лазер" >> "$OUTPUT_FILE"
echo "M2 ; Конец программы" >> "$OUTPUT_FILE"

echo "--------------------------------------------------"
echo " Конвертация успешно завершена на 100%!"
echo " Результат записан в: $OUTPUT_FILE"
echo "=================================================="
exit 0
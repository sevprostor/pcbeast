#!/bin/bash

# Создаем папку для конфигов, если её нет
mkdir -p "./confs"
CONFIG_FILE="${1:-./confs/pcbeast.conf}"
CONF_NAME="pcbeast.conf"

# 1. ЧТЕНИЕ КОНФИГА (Только чтение, без автоматической записи)
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Дефолтные значения на случай, если в конфиге чего-то нет
: "${SRC_DIR:=./svg}"
: "${CONF_NEED_CONVERT:=YES}"
: "${STEP1_FILE:=base.svg}"
: "${STEP1_OFFSET:=0.1}"
: "${STEP2_FILE:=base_poly_offset.svg}"
: "${STEP2_WIDTH:=1}"
: "${STEP3_FILE:=base_isolated.svg}"
: "${STEP3_HEIGHT:=0.05}"
: "${STEP4_FILE:=base_isolated.stl}"
: "${STEP4_PRUSA_INI:=pcb-prusa.ini}"
: "${STEP5_FILE:=base_isolated.gcode}"
: "${STEP5_FEED:=5000}"
: "${STEP5_POWER:=500}"

# Сохраняем исходные значения для отслеживания изменений
OLD_SRC_DIR="$SRC_DIR"
OLD_CONF_NEED_CONVERT="$CONF_NEED_CONVERT"
OLD_STEP1_FILE="$STEP1_FILE" ; OLD_STEP1_OFFSET="$STEP1_OFFSET"
OLD_STEP2_FILE="$STEP2_FILE" ; OLD_STEP2_WIDTH="$STEP2_WIDTH"
OLD_STEP3_FILE="$STEP3_FILE" ; OLD_STEP3_HEIGHT="$STEP3_HEIGHT"
OLD_STEP4_FILE="$STEP4_FILE" ; OLD_STEP4_PRUSA_INI="$STEP4_PRUSA_INI"
OLD_STEP5_FILE="$STEP5_FILE" ; OLD_STEP5_FEED="$STEP5_FEED" ; OLD_STEP5_POWER="$STEP5_POWER"

# 2. СТАРТОВОЕ МЕНЮ (Выбор начального шага)
START_STEP=$(whiptail --title "PCBEAST - Выбор режима" --radiolist \
"Выберите шаг, с которого начнется работа:" 16 65 5 \
"1" "Шаг 1: svg-offset.sh (Склейка полигона, припуск)" ON \
"2" "Шаг 2: svg-isolator.sh (Выворотка, изоляция)" OFF \
"3" "Шаг 3: svgtostl.sh (SVG > STL)" OFF \
"4" "Шаг 4: stltogcode.sh (Слайсинг Prusa)" OFF \
"5" "Шаг 5: prntocnc.sh (Конверсия G-кода)" OFF 3>&1 1>&2 2>&3)

if [ $? -ne 0 ] || [ -z "$START_STEP" ]; then exit 0; fi


# 3. ПОШАГОВЫЙ ВИЗАРД НАСТРОЙКИ ПАРАМЕТРОВ
SRC_DIR=$(whiptail --title "Глобальные настройки" --inputbox "Укажите путь к каталогу исходных файлов:" 10 60 "$SRC_DIR" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi

# Настройка флагов для радиолиста конвертации
RAD_YES="OFF"; RAD_NO="OFF"
if [ "$CONF_NEED_CONVERT" = "NO" ]; then RAD_NO="ON"; else RAD_YES="ON"; fi

# Экран выбора необходимости конвертации на Шаге 5
CONF_NEED_CONVERT=$(whiptail --title "Настройка параметров" --radiolist \
"Выполнить финальную конвертацию G-кода для FluidNC (ОЧЕНЬ ДОЛГО)?" 12 65 2 \
"YES" "Да, конвертировать в лазерный G-код" $RAD_YES \
"NO"  "Нет, пропустить этот этап" $RAD_NO 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi

if [ "$START_STEP" -le 1 ]; then
    STEP1_FILE=$(whiptail --title "Шаг 1: Настройка" --inputbox "Имя исходного файла SVG:" 10 60 "$STEP1_FILE" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi

    STEP1_OFFSET=$(whiptail --title "Шаг 1: Настройка" --inputbox "Величина припуска (мм):" 10 60 "$STEP1_OFFSET" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi
fi

if [ "$START_STEP" -le 2 ]; then
    if [ "$START_STEP" -eq 2 ]; then
        STEP2_FILE=$(whiptail --title "Шаг 2: Настройка" --inputbox "Имя исходного файла SVG (полигоны):" 10 60 "$STEP2_FILE" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi
    fi
    STEP2_WIDTH=$(whiptail --title "Шаг 2: Настройка" --inputbox "Ширина изолирующего контура:" 10 60 "$STEP2_WIDTH" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi
fi

if [ "$START_STEP" -le 3 ]; then
    if [ "$START_STEP" -eq 3 ]; then
        STEP3_FILE=$(whiptail --title "Шаг 3: Настройка" --inputbox "Имя изолированного файла SVG:" 10 60 "$STEP3_FILE" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi
    fi
    STEP3_HEIGHT=$(whiptail --title "Шаг 3: Настройка" --inputbox "Высота выдавливания STL (мм). От этого зависит количество слоев (проходов):" 10 60 "$STEP3_HEIGHT" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi
fi

if [ "$START_STEP" -le 4 ]; then
    if [ "$START_STEP" -eq 4 ]; then
        STEP4_FILE=$(whiptail --title "Шаг 4: Настройка" --inputbox "Имя исходного файла STL:" 10 60 "$STEP4_FILE" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi
    fi
    STEP4_PRUSA_INI=$(whiptail --title "Шаг 4: Настройка" --inputbox "Имя профиля Prusa (.ini в ./confs):" 10 60 "$STEP4_PRUSA_INI" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi
fi

# Параметры 5-го шага запрашиваем только если в конвейере активна конвертация
if [ "$START_STEP" -le 5 ] && [ "$CONF_NEED_CONVERT" = "YES" ]; then
    if [ "$START_STEP" -eq 5 ]; then
        STEP5_FILE=$(whiptail --title "Шаг 5: Настройка" --inputbox "Имя файла принтерного G-кода:" 10 60 "$STEP5_FILE" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi
    fi
    STEP5_FEED=$(whiptail --title "Шаг 5: Настройка" --inputbox "Скорость подачи (F):" 10 60 "$STEP5_FEED" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi

    STEP5_POWER=$(whiptail --title "Шаг 5: Настройка" --inputbox "Мощность (S):" 10 60 "$STEP5_POWER" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then whiptail --msgbox "Операция отменена." 8 40; exit 0; fi
fi


# 4. ПРОВЕРКА ИЗМЕНЕНИЙ И ПРЕДЛОЖЕНИЕ СОХРАНЕНИЯ
DATA_CHANGED=false
if [ "$SRC_DIR" != "$OLD_SRC_DIR" ] || [ "$CONF_NEED_CONVERT" != "$OLD_CONF_NEED_CONVERT" ] || \
   [ "$STEP1_FILE" != "$OLD_STEP1_FILE" ] || [ "$STEP1_OFFSET" != "$OLD_STEP1_OFFSET" ] || \
   [ "$SRC_DIR/$STEP2_FILE" != "$SRC_DIR/$OLD_STEP2_FILE" ] || [ "$STEP2_WIDTH" != "$OLD_STEP2_WIDTH" ] || \
   [ "$SRC_DIR/$STEP3_FILE" != "$SRC_DIR/$OLD_STEP3_FILE" ] || [ "$STEP3_HEIGHT" != "$OLD_STEP3_HEIGHT" ] || \
   [ "$SRC_DIR/$STEP4_FILE" != "$SRC_DIR/$OLD_STEP4_FILE" ] || [ "$STEP4_PRUSA_INI" != "$OLD_STEP4_PRUSA_INI" ] || \
   [ "$SRC_DIR/$STEP5_FILE" != "$SRC_DIR/$OLD_STEP5_FILE" ] || [ "$STEP5_FEED" != "$OLD_STEP5_FEED" ] || [ "$STEP5_POWER" != "$OLD_STEP5_POWER" ]; then
    DATA_CHANGED=true
fi

if [ "$DATA_CHANGED" = true ]; then
    NEW_CONF_NAME=$(whiptail --title "Сохранить конфиг?" \
        --ok-button "Сохранить" \
        --cancel-button "Пропустить" \
        --inputbox "Данные были изменены. Введите имя файла конфигурации для сохранения (в ./confs):" \
        11 65 "$CONF_NAME" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ]; then
        [[ "$NEW_CONF_NAME" != *.conf ]] && NEW_CONF_NAME="${NEW_CONF_NAME}.conf"
        
        cat << EOF > "./confs/$NEW_CONF_NAME"
SRC_DIR="$SRC_DIR"
CONF_NEED_CONVERT="$CONF_NEED_CONVERT"
STEP1_FILE="$STEP1_FILE"
STEP1_OFFSET="$STEP1_OFFSET"
STEP2_FILE="$STEP2_FILE"
STEP2_WIDTH="$STEP2_WIDTH"
STEP3_FILE="$STEP3_FILE"
STEP3_HEIGHT="$STEP3_HEIGHT"
STEP4_FILE="$STEP4_FILE"
STEP4_PRUSA_INI="$STEP4_PRUSA_INI"
STEP5_FILE="$STEP5_FILE"
STEP5_FEED="$STEP5_FEED"
STEP5_POWER="$STEP5_POWER"
EOF
        whiptail --msgbox "Конфигурация успешно сохранена в ./confs/$NEW_CONF_NAME" 8 50
    fi
fi


# 5. БЛОК ВЫПОЛНЕНИЯ СКРИПТОВ С ПРЯМОЙ ТРАНСЛЯЦИЕЙ ВАШИХ МАРКЕРОВ XXX
LOG_FILE="/tmp/pcbeast_run.log"
echo "=== Старт сессии PCBEAST: $(date) ===" > "$LOG_FILE"

# Конвейер обработки полностью прозрачен. Всё, что ваши внутренние скрипты 
# пишут в STDOUT (включая маркеры XXX), улетает прямиком в whiptail gauge.
# Всё, что пишется в STDERR (ошибки), дублируется в лог-файл.
{
    # Шаг 1
    if [ "$START_STEP" -le 1 ]; then
        ./svg-offset.sh "$SRC_DIR/$STEP1_FILE" "$STEP1_OFFSET" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then exit 1; fi
        STEP2_FILE=$(basename "$STEP1_FILE" .svg)"_poly_offset.svg"
        echo "XXX"
        echo "20"
        echo "Выполнение ./svg-offset.sh $SRC_DIR/$STEP1_FILE $STEP1_OFFSET"
        echo "Слияние всех элементов в полигоны и добавление припуска > $STEP2_FILE"
        echo "XXX"
    fi

    # Шаг 2
    if [ "$START_STEP" -le 2 ]; then
        ./svg-isolator.sh "$SRC_DIR/$STEP2_FILE" "$STEP2_WIDTH" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then exit 1; fi
        STEP3_FILE=$(basename "$STEP2_FILE" .svg)"_isolated.svg"
        echo "XXX"
        echo "40"
        echo "Выполнение ./svg-isolator.sh $SRC_DIR/$STEP2_FILE $STEP2_WIDTH"
        echo "Выворотка и добавление изоляционной обводки > $STEP3_FILE"
        echo "XXX"
    fi

    # Шаг 3
    if [ "$START_STEP" -le 3 ]; then
        ./svgtostl.sh "$SRC_DIR/$STEP3_FILE" "$STEP3_HEIGHT" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then exit 1; fi
        STEP4_FILE=$(basename "$STEP3_FILE" .svg)".stl"
        echo "XXX"
        echo "60"
        echo "Выполнение ./svgtostl.sh $SRC_DIR/$STEP3_FILE $STEP3_HEIGHT"
        echo "Вытяжка призмы > $STEP4_FILE"
        echo "XXX"
    fi

    # Шаг 4
    if [ "$START_STEP" -le 4 ]; then
        ./stltogcode.sh "$SRC_DIR/$STEP4_FILE" "./confs/$STEP4_PRUSA_INI" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        if [ ${PIPESTATUS[0]} -ne 0 ]; then exit 1; fi
        STEP5_FILE=$(basename "$STEP4_FILE" .stl)".gcode"
        echo "XXX"
        echo "80"
        echo "Выполнение ./stltogcode.sh $SRC_DIR/$STEP4_FILE ./confs/$STEP4_PRUSA_INI"
        echo "Генерация gcode > $STEP5_FILE"
        echo "XXX"
    fi

    # Шаг 5
    if [ "$START_STEP" -le 5 ]; then
        if [ "$CONF_NEED_CONVERT" = "YES" ]; then
            ./prntocnc.sh "$SRC_DIR/$STEP5_FILE" "$STEP5_FEED" "$STEP5_POWER" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
            if [ ${PIPESTATUS[0]} -ne 0 ]; then exit 1; fi
            echo "XXX"
            echo "95"
            echo "Выполнение ./prntocnc.sh $SRC_DIR/$STEP5_FILE $STEP5_FEED $STEP5_POWER"
            echo "Конвертация Klipper > FluidNC"
            echo "XXX"
            sleep 1
        else
            echo "XXX\n95\nШаг 5 отключен. Завершение...\nXXX"
            echo "Конвертация G-кода отключена пользователем в конфигурации." >> "$LOG_FILE"
            sleep 1
        fi
    fi

    echo "XXX\n100\nГотово!\nXXX"
    sleep 1
} | whiptail --title "PCBEAST" --gauge "Запуск..." 12 75 0

# Проверка результатов через PIPESTATUS
if [ ${PIPESTATUS} -eq 0 ]; then
    rm -f "$LOG_FILE"
    whiptail --title "Успех" --msgbox "Все выбранные этапы успешно выполнены!\n\nРезультаты сохранены в папке: $SRC_DIR\n(Временный лог успешно удален)" 11 65
else
    whiptail --title "Ошибка" --msgbox "Произошел сбой при выполнении скриптов.\n\nПодробный лог сохранен для анализа в:\n$LOG_FILE" 11 65
fi
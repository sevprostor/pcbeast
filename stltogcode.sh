#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Использование: $0 <путь_к_file.stl> <путь_к_profile.ini>"
    exit 1
fi

STL_FILE="$1"
INI_FILE="$2"

if [ ! -f "$STL_FILE" ]; then echo "Ошибка: STL не найден"; exit 1; fi
if [ ! -f "$INI_FILE" ]; then echo "Ошибка: INI не найден"; exit 1; fi

echo "1. Анализ размеров модели..."
# Получаем информацию о модели из PrusaSlicer CLI через Flatpak
INFO=$(flatpak run com.prusa3d.PrusaSlicer --info "$STL_FILE")

# Извлекаем чистые размеры по осям X и Y
SIZE_X=$(echo "$INFO" | grep "size_x" | awk '{print $3}' | tr -d '\r')
SIZE_Y=$(echo "$INFO" | grep "size_y" | awk '{print $3}' | tr -d '\r')

# Проверка, что размеры успешно считались
if [ -z "$SIZE_X" ] || [ -z "$SIZE_Y" ]; then
    echo "Ошибка: Не удалось определить размеры модели."
    exit 1
fi

echo "Исходный размер модели: X = ${SIZE_X}мм, Y = ${SIZE_Y}мм"

# Округляем размеры в большую сторону (ceil) до целых миллиметров с помощью bc
# Добавляем 0.999 и отсекаем дробную часть через scale=0
BED_X=$(echo "scale=0; ($SIZE_X + 0.999999) / 1" | bc)
BED_Y=$(echo "scale=0; ($SIZE_Y + 0.999999) / 1" | bc)

echo "Округленный размер стола: X = ${BED_X}мм, Y = ${BED_Y}мм"

# Формируем полигон стола в формате 0x0,Xx0,XxY,0xY с целыми числами
BED_SHAPE="0x0,${BED_X}x0,${BED_X}x${BED_Y},0x${BED_Y}"

echo "2. Нарезка..."
# Выводим точную команду, которая будет запущена
echo "Запуск команды: flatpak run com.prusa3d.PrusaSlicer --slice --load \"$INI_FILE\" --bed-shape \"$BED_SHAPE\" \"$STL_FILE\""

# Запускаем слайсинг с автоматическим центрированием на новом столе
flatpak run com.prusa3d.PrusaSlicer --slice \
    --load "$INI_FILE" \
    --bed-shape "$BED_SHAPE" \
    "$STL_FILE"

if [ $? -eq 0 ]; then
    echo "Успешно! G-код готов, модель автоматически отцентрирована на столе."
else
    echo "Ошибка при генерации G-кода."
    exit 1
fi
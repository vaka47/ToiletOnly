# ToiletOnly Handoff

Дата handoff: 2026-03-27
Проект: `/Users/vaka47/Dev/Приложение в туалете`

## 1. Что это за проект

`ToiletOnly` — iOS-приложение, которое должно открывать доступ только тогда, когда камера видит реальный унитаз.

Целевое поведение:
- открывать сессию на 15 минут только при наведении на настоящий унитаз;
- не открываться на похожих белых объектах;
- работать офлайн на устройстве через Core ML.

## 2. Какое ТЗ мы фактически решали

Главная задача этого чата:
- собрать и дообучить модель распознавания унитаза;
- встроить ее в iOS-приложение;
- добиться, чтобы приложение не открывалось на ложных объектах вроде:
  - холодильника,
  - белого стула,
  - тумбы,
  - двери,
  - полотенца,
  - белья,
  - других крупных белых поверхностей.

Подзадачи:
- исправить проблемы Xcode/signing/install;
- починить встраивание Core ML модели в bundle приложения;
- проверить логику парсинга YOLO/CoreML-выхода;
- собрать hard-negative dataset и запустить новое обучение;
- подготовить проект к следующей итерации тестов уже с новой моделью.

## 3. Что было сделано по приложению

### 3.1. Xcode / проект / подпись

Исправлены реальные проблемы проекта:
- убран устаревший `OTHER_CODE_SIGN_FLAGS = --resource-rules ...` из `project.pbxproj`;
- убран неправильный folder reference для ресурсов;
- ресурсы добавлены корректно:
  - `Assets.xcassets`
  - `ToiletDetector.mlpackage`

Файл:
- `/Users/vaka47/Dev/Приложение в туалете/ToiletOnly.xcodeproj/project.pbxproj`

Результат:
- ранее `.app` собирался/подписывался некорректно;
- после исправлений `xcodebuild` начал успешно собирать и подписывать приложение.

### 3.2. Проблемы установки на iPhone

В чате были длительные проблемы с:
- trust / developer certificate;
- `CoreDeviceError`;
- `Could not attach to pid`;
- `Unable to download shared cache files`;
- нехваткой места под Xcode cache;
- stale build на телефоне.

Смысл для нового чата:
- это были в основном операционные проблемы окружения;
- проект сейчас в состоянии, где он собирается;
- но при следующих тестах все равно нужно следить, что на iPhone действительно ставится свежая сборка, а не старый билд.

## 4. Что было сделано по модели и детектору

### 4.1. Встроенная модель

Модель в приложении лежит здесь:
- `/Users/vaka47/Dev/Приложение в туалете/ToiletOnly/Resources/ToiletDetector.mlpackage`

Ранее уже проверялось, что встроенная модель совпадала с экспортированной Core ML моделью на одном из этапов. Но текущее состояние приложения на телефоне еще не переведено на новую `v6` модель с hard negatives.

### 4.2. Парсинг Core ML / YOLO выхода

В ходе чата выяснилось, что выход у модели YOLO-подобный, форма:
- `1 x 5 x 4116`

Была исправлена логика парсинга:
- каналы трактуются как `x, y, w, h, conf`;
- `sigmoid` не применяется к геометрии bbox;
- добавлялась логика выбора лучшего кандидата и геометрические фильтры.

Основной файл:
- `/Users/vaka47/Dev/Приложение в туалете/ToiletOnly/Sources/Detectors/ToiletDetector.swift`

### 4.3. Пост-фильтрация в приложении

После ложных срабатываний на белые объекты в код добавлялись:
- геометрические фильтры bbox;
- scoring через форму/размер/позицию bbox;
- ужесточенные пороги;
- окно попаданий / серия для unlock-логики.

Основной файл логики разблокировки:
- `/Users/vaka47/Dev/Приложение в туалете/ToiletOnly/Sources/Views/AccessViewModel.swift`

Текущее состояние кода на момент handoff:
- `ToiletDetector.swift`
  - `minimumToiletConfidence = 0.70`
- `AccessViewModel.swift`
  - `windowSize = 10`
  - `requiredHits = 5`
  - `requiredStreak = 3`
  - `minConfidence = 0.70`

Важно:
- это не финальная подтвержденная логика;
- эти фильтры на каком-то этапе стали слишком жесткими, и пользователь получил `0%` даже на реальном унитазе;
- поэтому корневой фокус сместился с кода на переобучение модели с hard negatives.

## 5. Что было установлено по качеству старой модели

Старая модель `v5` давала хорошие офлайн-метрики, но плохо вела себя в реальном приложении.

### 5.1. `v5` train/val

Run:
- `/Volumes/Untitled/ToiletML/runs/toilet_v5_cpu_stable`

Финальная строка `results.csv`:
- precision: `0.87078`
- recall: `0.88486`
- mAP50: `0.91819`
- mAP50-95: `0.77386`

Файл:
- `/Volumes/Untitled/ToiletML/runs/toilet_v5_cpu_stable/results.csv`

### 5.2. `v5` test (из пользовательского лога в чате)

На test split пользователь получил:
- images: `627`
- instances: `711`
- precision: `0.886`
- recall: `0.802`
- mAP50: `0.877`
- mAP50-95: `0.731`

Вывод:
- офлайн-метрики были сильные;
- но на телефоне модель путала унитаз с белыми объектами;
- значит метрик было недостаточно, не хватало hard negatives.

## 6. Как вела себя старая встроенная модель в приложении

Реальные симптомы из чата:
- на унитазе часто было `70%`, но unlock не происходил;
- на белом стуле, холодильнике, белье и других белых поверхностях confidence мог быть выше, чем на унитазе;
- приложение иногда открывалось на всем подряд;
- после усиления фильтров приложение стало местами не реагировать даже на настоящий унитаз.

Ключевой вывод:
- проблема в основном не в UI и не только в порогах;
- модель плохо различала `toilet` и hard negatives;
- кодом это можно только частично подавлять.

## 7. Что было сделано для hard negatives

### 7.1. Собран новый pipeline

В проекте подготовлен pipeline для hard-negative обучения.

Скрипты:
- `/Users/vaka47/Dev/Приложение в туалете/ml/scripts/append_backgrounds_to_lists.py`
- `/Users/vaka47/Dev/Приложение в туалете/ml/scripts/prepare_hard_negative_lists_from_v5.sh`
- `/Users/vaka47/Dev/Приложение в туалете/ml/scripts/build_background_yolo_dataset.py`
- `/Users/vaka47/Dev/Приложение в туалете/ml/scripts/build_objects365_background_yolo.py`
- `/Users/vaka47/Dev/Приложение в туалете/ml/scripts/bootstrap_hard_negative_dataset.sh`
- `/Users/vaka47/Dev/Приложение в туалете/ml/scripts/extract_video_frames.py`

Дополнительно обновлен:
- `/Users/vaka47/Dev/Приложение в туалете/ml/scripts/requirements.txt`

### 7.2. Классы hard negatives и источники

Файлы:
- `/Users/vaka47/Dev/Приложение в туалете/ml/data/openimages_hard_negative_classes.txt`
- `/Users/vaka47/Dev/Приложение в туалете/ml/data/objects365_hard_negative_classes.txt`
- `/Users/vaka47/Dev/Приложение в туалете/ml/data/negative_pack_sources.md`

Туда уже заложены нужные категории:
- `Chair`
- `Stool`
- `Refrigerator`
- `Cabinetry`
- `Cabinet/shelf`
- `Door`
- `Bed`
- `Towel`
- `Sink`
- `Bathtub`
- `Washing machine`
- `Dishwasher`
- `Toilet paper`
- и другие бытовые indoor-классы

### 7.3. README по новому пайплайну

Файл:
- `/Users/vaka47/Dev/Приложение в туалете/ml/README.md`

Там уже описаны:
- hard-negative datasets;
- готовые пакеты Open Images / Objects365;
- видео-кадры для negatives;
- сборка background-only YOLO датасета;
- list-based retrain поверх `v5`.

## 8. Новый dataset `v6_from_v5` с исключениями

Мы не пересобирали все с нуля. Вместо этого:
- взяли реальную рабочую `v5` list-based базу;
- добавили к ней hard negatives.

### 8.1. Итоговые списки

Файлы:
- `/Users/vaka47/Dev/Приложение в туалете/ml/data/lists_v6_from_v5/train.txt`
- `/Users/vaka47/Dev/Приложение в туалете/ml/data/lists_v6_from_v5/val.txt`
- `/Users/vaka47/Dev/Приложение в туалете/ml/data/lists_v6_from_v5/test.txt`

Размеры:
- train: `10063`
- val: `1202`
- test: `827`

### 8.2. YAML

Файл:
- `/Users/vaka47/Dev/Приложение в туалете/ml/data/toilet_noncommercial_v6_from_v5_lists.yaml`

Содержимое:
- `train` указывает на `lists_v6_from_v5/train.txt`
- `val` указывает на `lists_v6_from_v5/val.txt`
- `test` указывает на `lists_v6_from_v5/test.txt`
- `names[0] = toilet`

### 8.3. Objects365 hard negatives

На этом этапе реально были добавлены `Objects365` hard negatives.

Рабочие директории:
- `/Users/vaka47/Dev/Приложение в туалете/ml/data/work_v6_from_v5/objects365_hard_negatives_yolo`
- `/Users/vaka47/Dev/Приложение в туалете/ml/data/work_v6_from_v5/objects365_hard_negatives_split_yolo`

Что было сделано:
- выбрано `2000` background-only изображений;
- `116` изображений были исключены, потому что содержали `Toilet`;
- split:
  - train: `1600`
  - val: `200`
  - test: `200`

## 9. Новый train `v6_from_v5_hardneg`

### 9.1. Run

Папка run:
- `/Volumes/Untitled/ToiletML/runs/toilet_v6_from_v5_hardneg`

Веса:
- `/Volumes/Untitled/ToiletML/runs/toilet_v6_from_v5_hardneg/weights/best.pt`
- `/Volumes/Untitled/ToiletML/runs/toilet_v6_from_v5_hardneg/weights/last.pt`

Оба файла сейчас существуют.

### 9.2. Команда обучения

```bash
caffeinate -dimsu env TMPDIR=/Volumes/Untitled/ToiletML/tmp \
yolo detect train \
  model="/Users/vaka47/Dev/Приложение в туалете/yolov8n.pt" \
  data="/Users/vaka47/Dev/Приложение в туалете/ml/data/toilet_noncommercial_v6_from_v5_lists.yaml" \
  epochs=40 imgsz=448 batch=8 device=cpu workers=0 \
  val=False plots=False \
  project="/Volumes/Untitled/ToiletML/runs" name=toilet_v6_from_v5_hardneg
```

### 9.3. Итоговые метрики `v6`

Из:
- `/Volumes/Untitled/ToiletML/runs/toilet_v6_from_v5_hardneg/results.csv`

Финальная строка:
- epoch: `40`
- train/box_loss: `0.63543`
- train/cls_loss: `0.57185`
- train/dfl_loss: `0.99781`
- precision: `0.9203`
- recall: `0.8375`
- mAP50: `0.90879`
- mAP50-95: `0.76653`
- val/box_loss: `0.58379`
- val/cls_loss: `0.66566`
- val/dfl_loss: `0.90495`

Что это значит:
- hard negatives не развалили модель;
- precision стал выше, recall слегка ниже по сравнению с `v5`;
- офлайн метрики у `v6` выглядят жизнеспособно;
- но мы еще не проверили ее в приложении на iPhone.

## 10. Что еще не сделано

Критично: новая `v6` модель пока не доведена до конца в app loop.

Еще НЕ сделано:
- не выполнен test/val для `v6` на `split=test`;
- не экспортирован `best.pt` из `v6` в Core ML;
- не заменена встроенная модель приложения на `v6`;
- не проведен новый реальный тест на iPhone с `v6`.

То есть текущий stop-point такой:
- новый retrain с hard negatives уже завершен;
- новые веса готовы;
- приложение еще не проверено с новой моделью.

## 11. Следующий шаг, который нужно сделать в новом чате

Порядок действий:

1. Прогнать `test` для `v6`:

```bash
yolo detect val \
  model="/Volumes/Untitled/ToiletML/runs/toilet_v6_from_v5_hardneg/weights/best.pt" \
  data="/Users/vaka47/Dev/Приложение в туалете/ml/data/toilet_noncommercial_v6_from_v5_lists.yaml" \
  split=test \
  device=cpu \
  imgsz=448 \
  batch=8
```

2. Экспортировать `best.pt` в Core ML.

Если нужен готовый скрипт, в проекте уже есть:
- `/Users/vaka47/Dev/Приложение в туалете/ml/scripts/export_coreml.py`

3. Подменить встроенную модель приложения:
- заменить содержимое:
  - `/Users/vaka47/Dev/Приложение в туалете/ToiletOnly/Resources/ToiletDetector.mlpackage`

4. Пересобрать и установить app на iPhone.

5. Проверить минимум на 4 сценах:
- реальный унитаз целиком;
- унитаз под углом;
- белый стул;
- холодильник / белая тумба / крупная белая поверхность.

6. Если новая модель все еще путает унитаз и стул/холодильник:
- уже дальше подправлять не пороги, а датасет следующей волной hard negatives.

## 12. Что важно помнить новому чату

Ключевой вывод этого чата:
- дело не только в коде;
- старая модель реально ранжировала белые объекты как `toilet`;
- поэтому был запущен новый `v6` retrain с hard negatives;
- именно с ним надо продолжать работу, а не снова бесконечно крутить пороги на старой встроенной модели.

Текущая рабочая гипотеза:
- после замены модели на `v6` ложные срабатывания должны уменьшиться;
- после этого уже имеет смысл снова докручивать пороги и unlock-логику в `ToiletDetector.swift` и `AccessViewModel.swift`.

## 13. Короткий prompt для нового чата

В новый чат можно вставить этот файл и написать примерно так:

> Продолжай с этого handoff.  
> Проект: `/Users/vaka47/Dev/Приложение в туалете`  
> Нужно взять `v6` hard-negative модель, прогнать `test`, экспортировать в Core ML, встроить в `ToiletOnly`, собрать приложение и продолжить реальные проверки на iPhone.

## 14. Что можно игнорировать

В текущем чате был позже один отдельный запрос по PDF/книге/раскадровке первой главы. Он не относится к `ToiletOnly` и не является частью этого handoff.

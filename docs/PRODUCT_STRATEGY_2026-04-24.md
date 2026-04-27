# Product Strategy

## Текущее состояние

Уже есть:

- iOS клиент с unlock через camera gate
- встроенная `v6` модель детекции унитаза
- исключения для chair / fridge / lookalikes
- регистрация с полом, предпочтениями, возрастом, био и фото
- гео-лента с онлайн-приоритетом
- лайк, скип, суперлайк с сообщением
- чат и пинг в онлайн
- активность по лайкам и видео
- видео-лента текущих сессий
- редактирование профиля и архив видео
- блокировка и управление block list

## Что должно стать beta-ready

### 1. Core social loop

- стабилизировать match keep flow на обе стороны
- улучшить empty states при отсутствии людей поблизости
- добавить явный `like back` и `open chat` path везде, где это уместно
- ввести нормальный activity badge counter

### 2. Video loop

- добавить face lock indicator еще заметнее во время записи
- улучшить playback UX на `Интересное`
- добавить переход из activity к автору и связанному видео
- продумать moderation queue для flagged videos

### 3. Trust and safety

- server-side rate limits
- report review queue
- basic anti-spam heuristics
- device fingerprint / multi-account friction
- policy copy in onboarding and upload flows

### 4. ML unlock

- собрать еще real toilet examples
- отдельно собрать hard negatives: chair, cabinet, washing machine, bedside table, sink area
- считать false-open rate и false-reject rate
- держать коммерчески чистый training mix

## KPI на ближайшие 6 недель

- `unlock success >= 75%` на валидных туалетах
- `false open < 2%` на основных hard negatives
- `profile completion >= 65%`
- `like -> match >= 18%`
- `match -> first message >= 45%`
- `session video publish rate >= 20%`
- `D1 >= 30%` у активированных пользователей

## Roadmap

### 2 недели

- UI polish feed / videos / profile / activity
- bugfix pass on matching and timers
- ML hard-negative validation
- investor demo script

### 6 недель

- analytics instrumentation
- push and badge quality pass
- moderation admin basics
- subscription scaffolding
- better onboarding completion funnel

### 3 месяца

- growth experiments
- subscription launch
- retention loops around sessions and videos
- authenticity and anti-abuse stack

## Что еще не закрыто

- полноценный notification center с badge count
- admin tools for reports
- legal / privacy / deletion flows production quality
- deeper analytics across the funnel
- larger-scale ML eval on new toilet types

## Правило продуктовых решений

Все новые доработки должны отвечать минимум одному из трех вопросов:

1. Это повышает unlock-to-session conversion?
2. Это повышает match-to-chat conversion?
3. Это повышает session retention without killing trust?

Если ответ `нет`, фича не должна идти раньше safety, retention и monetization basics.

# Investor Demo

## Что это

`Toilet Dating` это session-based social discovery продукт.
Приложение открывается только после real-world gate: камера должна увидеть унитаз.
После этого пользователь получает живую 15-минутную сессию с людьми поблизости.

Ключевая идея для инвестора:
- не очередной swipe-app
- не бесконечный low-intent dating feed
- а новый social primitive: короткая подтвержденная локальная сессия с высоким намерением

## Почему это может выстрелить

- У продукта есть жесткий входной ритуал. Это убирает часть фейков, пассивных пользователей и случайного трафика.
- Сессия короткая. Это поднимает urgency, ответные действия и конверсию в диалог.
- Внутри одной сессии соединяются три механики: unlock by real-world context, swipe discovery, short-form video.
- Контент не просто копится, а живет в окне времени. Это создает FOMO и частоту возвратов.

## Что показывать на демо

1. Unlock flow.
   Наведение камеры на унитаз, подтверждение доступа, запуск 15-минутной сессии.

2. Onboarding.
   Выбор своего гендера и гендеров показа, возраст, описание, до `10` фото, toilet selfie.

3. Feed.
   Карточка профиля без наложения кнопок на фото.
   Отдельный action dock: `скип`, `лайк`, `суперлайк`, `видео`.
   Сверху таймер активной сессии.

4. Match.
   Взаимный лайк, чат, пинг в онлайн, ограничение жизни мэтча по сессиям.

5. Video.
   Короткое видео из текущей сессии.
   Лента `Интересное` с сортировкой по близости, популярности и свежести.
   Таймер жизни сессии на карточке видео.

6. Activity / Inbox.
   Кто лайкнул, кто отправил суперлайк, кто позвал в онлайн, кто отреагировал на видео.
   Быстрый `лайк в ответ`.

7. Safety.
   Видео записывается только когда лицо в кадре.
   Если лицо пропадает, запись останавливается.
   Детектор унитаза не пускает по стулу и холодильнику.

## Что говорить в цифрах

На встрече инвестору нужны не фичи, а воронка:

- `unlock success rate`
- `profile completion rate`
- `like -> match`
- `match -> first message`
- `message -> kept match`
- `video view -> reaction/comment`
- `D1`, `D7`, `weekly session frequency`

Если этих данных пока нет, нужно прямо говорить:
сейчас продукт в beta-build стадии, ближайшая цель не revenue, а подтверждение retention and intent.

## Как подавать рынок

Питч лучше строить не как meme dating app.
Правильная формулировка:

`We are building a high-intent, real-world-gated social graph for short live sessions.`

Это позволяет обсуждать не только dating, но и более широкий category:
- live proximity social
- ephemeral local discovery
- authenticity-first matching

## Монетизация

Первая понятная модель:

- подписка
- дополнительные суперлайки
- boost в ленте
- расширенный радиус
- rewind
- advanced filters

Позже:
- creator tools for session videos
- geo-based premium discovery packs

## Честные риски

- ниша может оказаться слишком узкой без расширения positioning
- moderation и abuse control станут bottleneck очень быстро
- privacy / consent / age safety нужно довести до production-grade уровня до масштабирования
- ML gate надо еще валидировать на большем количестве реальных туалетов и hard negatives

## Ближайший narrative для инвестора

`We already have a working product loop, a live unlock mechanism, session-based matching, video discovery, and an improving real-world ML gate. The next milestone is proving that real-world gating increases intent, match quality, and session retention relative to generic dating flows.`

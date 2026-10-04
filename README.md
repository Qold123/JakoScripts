# JakoScripts — MM2

Скрипт для Murder Mystery 2. Оформление — VANTA Style A «Dark Violet Glass».

```
JakoScripts | MM2  v3.0
окно 480x360 · сайдбар 150 · Combat / Visuals / Movement / Config · RightShift
```

## Установка

**Приватный репозиторий (как сейчас).** Вставь в инжектор содержимое `JakoScripts_bootstrap.lua`, предварительно положив свой токен в `CFG.token`:

1. GitHub → Settings → Developer settings → Fine-grained tokens → Generate new token
2. Repository access — только `JakoScripts`
3. Permissions → Contents → **Read-only**
4. Токен идёт в `CFG.token`, весь файл вставляется в инжектор

Токен лежит внутри скрипта: кто получил файл — получил токен. Поэтому только fine-grained, только один репозиторий, только чтение. Отзывается одной кнопкой в настройках GitHub.

**Публичный репозиторий.** Одна строка, токен не нужен:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/JakoScripts/JakoScripts/main/JakoScripts_loader.lua"))()
```

**Локально.** Если файл лежит в workspace экзекутора:

```lua
loadstring(readfile("JakoScripts.lua"))()
```

## Обновление

Репозиторий — источник. Патч `JakoScripts.lua` подтягивается при следующем запуске, строку в инжекторе менять не нужно.

## Файлы

| Файл | Что это |
|---|---|
| `JakoScripts.lua` | основной скрипт, 2170 строк |
| `JakoScripts_bootstrap.lua` | короткий вход для приватного репо (токен) |
| `JakoScripts_loader.lua` | лоадер с миррорами и локальным фолбэком |
| `JakoScripts_preview.py` | генератор мокапа интерфейса |
| `JakoScripts_style_a_preview.png` | превью дизайна, 2x |
| `JakoScripts_check.py` | структурная проверка Luau (скобки, блоки, скоуп) |

## Возможности

**Combat** — аимбот (FOV, плавность, часть тела, hold RMB, проверка видимости через raycast), автострельба, kill aura с радиусом, автоЭкип инструмента.

**Visuals** — ESP по ролям (убийца / шериф / невинные) с `Highlight DepthMode.AlwaysOnTop`, ник с тегом `[M]/[S]/[I]`, дистанция, хп, трассеры, предметы (монеты, выпавший пистолет), fullbright с полным восстановлением света.

**Movement** — спидхак, прыжок, noclip с восстановлением коллизий, бесконечный прыжок, fly (клавиатура + мобильный джойстик), магнит монет, телепорт к пистолету.

**Config** — переназначение клавиши, прозрачность панели, акрил, вотермарка, уведомления, save / load / reset профиля, unload.

## Требования

Экзекутор уровня Delta / Solara / Xeno / Wave / Evon. `Drawing` — опционально: без него трассеры и FOV-круг отключаются, остальное работает. `firetouchinterest` нужен только для магнита монет.

## Дизайн

| Токен | Значение |
|---|---|
| surface | `#06060B` |
| glass | белый 6–10% + blur 28px |
| border / highlight | `#FFFFFF1C` / `#FFFFFF22` |
| accent | `#7C3AED` |
| icon | `#A78BFA` |
| text | `#FFFFFF` / `#A1A1AA` / `#71717A` |
| action | `#FFFFFF` на `#09090B` |
| row | `#FFFFFF08` / бордер `#FFFFFF0F` / радиус 12 |
| switch | ON `#7C3AED`, OFF `#FFFFFF1E` |
| slider | трек `#FFFFFF15`, заливка `#7C3AED → #C4B5FD` |

Шрифт Inter с откатом на Gotham. Иконки — lucide `target / eye / zap / settings`, нарисованы вектором. Эмодзи в интерфейсе нет.

![Style A](JakoScripts_style_a_preview.png)

# JakoScripts

Скрипты для Roblox. Оформление — VANTA Style A «Dark Violet Glass».

```
окно 480x360 · сайдбар 150 · Combat / Visuals / Movement / Config · RightShift
```

## Скрипты

| Игра | Файл | Вкладки | Ссылка для инжектора |
|---|---|---|---|
| Murder Mystery 2 | `JakoScripts.lua` | Combat · Visuals · Movement · Config | [vanta_mm2.lua](https://gist.githubusercontent.com/JakoScripts/d9426b0772256a4709608e96f710508d/raw/vanta_mm2.lua) |
| The Lost Front | `JakoScripts_lostfront.lua` | Combat · Visuals · Movement · Config | [vanta_lostfront.lua](https://gist.githubusercontent.com/JakoScripts/de7c068ca91e534ed54f3e64d191483f/raw/vanta_lostfront.lua) |
| Steal an Egg | `JakoScripts_stealegg.lua` | Farm · Visuals · Stealth · Config | [vanta_stealegg.lua](https://gist.githubusercontent.com/JakoScripts/5f6e4bcab0f3df2680a1944a29362b1a/raw/vanta_stealegg.lua) |
| Blade Ball | `JakoScripts_bladeball.lua` | Combat · Timing · Visuals · Config | [vanta_bladeball.lua](https://gist.githubusercontent.com/JakoScripts/0ce0c7ccfe1655547e19253ab16138b2/raw/vanta_bladeball.lua) |
| Deagle Duels | `JakoScripts_deagle.lua` | Combat · Visuals · Misc · Config | [vanta_deagle_duels.lua](https://gist.githubusercontent.com/JakoScripts/f037386d8aac2c924d78bee6157c3f66/raw/vanta_deagle_duels.lua) |
| FPV Drone Game | `JakoScripts_fpv_esp.lua` | Visuals · Drones · Config | [vanta_fpv_esp.lua](https://gist.githubusercontent.com/JakoScripts/61316c34897c57a840d0e1bdd24724ef/raw/vanta_fpv_esp.lua) |
| generic FPS | `JakoScripts_hitbox.lua` | Combat · Targets · Config | [vanta_hitbox.lua](https://gist.githubusercontent.com/JakoScripts/61e8e91041a490a3e8f258cfbbcc51c7/raw/vanta_hitbox.lua) |
| generic shooter | `JakoScripts_wh.lua` | Visuals · Config | [vanta_wh.lua](https://gist.githubusercontent.com/JakoScripts/455138e3d75b17f9610507f66b7594aa/raw/vanta_wh.lua) |

Запуск — одной строкой, подставь ссылку из таблицы:

```lua
loadstring(game:HttpGet("https://gist.githubusercontent.com/JakoScripts/<id>/raw/<file>.lua"))()
```

Локально, если файл лежит в workspace экзекутора:

```lua
loadstring(readfile("JakoScripts_wh.lua"))()
```

## Обновление

Репозиторий — источник. Правки идут в `main`, клиент тянет свежую версию при запуске: строку в инжекторе менять не нужно.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/JakoScripts/JakoScripts/main/JakoScripts_wh.lua"))()
```

Репозиторий приватный, поэтому raw без токена отдаёт 404 — либо публичный доступ, либо `JakoScripts_bootstrap.lua` с fine-grained PAT (Contents: Read-only) в `CFG.token`.

## Интерфейс

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

Шрифт Inter с откатом на Gotham. Иконки — lucide `target / eye / zap / settings`, нарисованы вектором. Эмодзи в интерфейсе нет. Клавиша скрытия окна — RightShift, переназначается в Config.

![Style A](JakoScripts_style_a_preview.png)

Превью остальных: `JakoScripts_<имя>_preview.png`.

## Файлы

| Файл | Что это |
|---|---|
| `StyleA_shell.lua` | шелл Style A, вшивается в каждый скрипт байт-в-байт |
| `JakoScripts_<игра>.lua` | скрипты, 947–1734 строк |
| `JakoScripts_bootstrap.lua` | вход для приватного репо (токен) |
| `JakoScripts_loader.lua` | лоадер с миррорами и локальным фолбэком |
| `JakoScripts_silencer.lua` | глушит нативные тосты Roblox (`SetCore SendNotification`) |
| `JakoScripts_preview.py` | рендер мокапа: читает вкладки прямо из кода |
| `JakoScripts_check.py` | структурная проверка Luau: блоки, вызовы, шелл-API, сервисы |
| `inject_shell.py` | вставка/обновление шелла по маркеру `-- @@SHELL@@` |
| `verify_refactor.py` | диф логики между исходником и рефактором |

## Заметки по сборке

Каждый скрипт собран одной заменой: старый UI-блок вырезан до маркера `-- @@SHELL@@`, игровая логика не тронута. Шелл подставляется скриптом, поэтому во всех восьми файлах он идентичен — правка шелла не требует ручной синхронизации:

```powershell
python inject_shell.py            # обновит шелл во всех JakoScripts_*.lua
python JakoScripts_check.py *.lua # структурная проверка
```

В гистах рядом с каждым скриптом лежит `*_obf.lua` — обфусцированная копия. Она собирается отдельным тулзом и после редизайна содержит старую версию: для обф-ссылок нужна переобфускация.

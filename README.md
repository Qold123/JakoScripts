# JakoScripts

Скрипты для Roblox. Оформление — VANTA Style A «Dark Violet Glass».

```
окно 480x360 · сайдбар 150 · Combat / Visuals / Movement / Config · RightShift
```

## Ссылки для инжектора

Репозиторий публичный, поэтому ссылка — обычный raw. Ни токена, ни заголовков.

| Скрипт | Ссылка | Вкладки |
|---|---|---|
| Murder Mystery 2 | [JakoScripts.lua](https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts.lua) | Combat · Visuals · Movement · Config |
| The Lost Front | [JakoScripts_lostfront.lua](https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts_lostfront.lua) | Combat · Visuals · Movement · Config |
| Pistol Arena | [JakoScripts_pistol.lua](https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts_pistol.lua) | Combat · Visuals · Movement · Config |
| Steal an Egg | [JakoScripts_stealegg.lua](https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts_stealegg.lua) | Farm · Visuals · Stealth · Config |
| Blade Ball | [JakoScripts_bladeball.lua](https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts_bladeball.lua) | Combat · Timing · Visuals · Config |
| Deagle Duels | [JakoScripts_deagle.lua](https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts_deagle.lua) | Combat · Visuals · Misc · Config |
| FPV Drone Game | [JakoScripts_fpv_esp.lua](https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts_fpv_esp.lua) | Visuals · Drones · Config |
| generic FPS | [JakoScripts_hitbox.lua](https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts_hitbox.lua) | Combat · Targets · Config |
| generic shooter | [JakoScripts_wh.lua](https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts_wh.lua) | Visuals · Targets · Config |

Запуск — одной строкой:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Qold123/JakoScripts/main/JakoScripts_pistol.lua"))()
```

Локально, если файл лежит в workspace экзекутора:

```lua
loadstring(readfile("JakoScripts_lostfront.lua"))()
```

## Обновление

Репозиторий — источник. Правки идут в `main`, клиент тянет свежую версию при
запуске: строку в инжекторе менять не нужно.

Если raw начнёт отдавать 404 — проверить ветку (`main`), имя файла и что
репозиторий остался публичным.

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

Шрифт Inter с откатом на Gotham. Иконки — lucide `target / eye / zap / settings`,
нарисованы вектором. Эмодзи в интерфейсе нет. Клавиша скрытия окна — RightShift,
переназначается в Config.

Текст шелла идёт с `AutoLocalize = false`: авто-локализация в CoreGui заставляет
движок дёргать `CoreGui.RobloxGui.Modules.Common.Locales` на каждую строку и под
экзекутором сыпет `attempt to call a nil value` в консоль.

![Style A](JakoScripts_style_a_preview.png)

Превью на каждый скрипт: `JakoScripts_<имя>_preview.png`.

## Файлы

| Файл | Что это |
|---|---|
| `StyleA_shell.lua` | шелл Style A, вшивается в каждый скрипт байт-в-байт |
| `JakoScripts_<игра>.lua` | скрипты |
| `JakoScripts_loader.lua` | лоадер с миррорами и локальным фолбэком |
| `JakoScripts_bootstrap.lua` | вход для приватного репозитория (токен) |
| `JakoScripts_silencer.lua` | глушит нативные тосты Roblox (`SetCore SendNotification`) |
| `light_obf.py` | сборка light obf: локальные в `_XX<n>`, строки в hex, комментарии срезаны |
| `obf_diff.py` | сверка токен-потоков обычного файла и обф-сборки |
| `inject_shell.py` | вставка/обновление шелла по маркеру `-- @@SHELL@@` |
| `JakoScripts_check.py` | структурная проверка Luau: блоки, вызовы, шелл-API, связка State ↔ UI |
| `JakoScripts_preview.py` | рендер мокапа: читает вкладки прямо из кода |
| `verify_refactor.py` | диф логики между исходником и рефактором |

## Как устроена сборка

Каждый скрипт собран одной заменой: старый UI-блок вырезан до маркера `-- @@SHELL@@`,
игровая логика не тронута. Шелл подставляется скриптом, поэтому во всех файлах он
идентичен — правка дизайна не требует ручной синхронизации.

```powershell
python inject_shell.py                    # обновить шелл во всех скриптах
python inject_shell.py JakoScripts_wh.lua # или в одном
python JakoScripts_check.py *.lua         # структурная проверка
python JakoScripts_preview.py --all       # перерендерить превью
```

Ворота перед пушем: `brackets: balanced`, `blocks: final depth = 0`,
`undefined-call scan: clean`, `shell wiring` видит все вкладки, `state keys`
показывает, что каждый ключ `State` привязан к UI.

## Заметки по граблям

- Приватный raw у GitHub не работает ни с `?token=`, ни с токеном в userinfo,
  ни через `github.com/.../raw`. Отвечает только запрос с заголовком
  `Authorization`, а его умеет `request` / `syn.request`. Отсюда
  `JakoScripts_bootstrap.lua`.
- `hookmetamethod` на `__namecall` обязан ставиться один раз на процесс.
  Повторная установка вешает новый слой поверх старого, старые замыкания держат
  мёртвое окружение, и консоль забивается `attempt to call a nil value` из
  CoreGui-модулей.
- `BlurEffect` в `Lighting` не удаляется сам: при повторном запуске старый надо
  снять, иначе они копятся.
- `filtergc`-реестр нельзя кэшировать навсегда: если игрока в нём нет, кэш надо
  сбросить, иначе сторона не определится до перезапуска.

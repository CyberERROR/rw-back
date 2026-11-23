<!-- ═══════════════════════════  HEADER  ═══════════════════════════ -->
<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&height=250&section=header&color=0:000000,40:030b1f,100:0a1a3f&text=RW-BACK&fontSize=72&fontColor=22D3EE&fontAlignY=36&desc=%D0%91%D1%8D%D0%BA%D0%B0%D0%BF%20%D0%91%D0%94%20Remnawave%20%2B%20Telegram-%D0%B1%D0%BE%D1%82&descSize=20&descAlignY=60&animation=fadeIn" width="100%" alt="rw-back"/>

<a href="https://github.com/CyberERROR/rw-back">
  <img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&weight=700&size=21&duration=2800&pause=900&color=00E5FF&center=true&vCenter=true&width=840&height=45&lines=%D0%AD%D0%BA%D1%81%D0%BF%D0%BE%D1%80%D1%82%20%D0%B1%D0%B0%D0%B7%D1%8B%20%D0%B2%20%D0%BE%D0%B4%D0%B8%D0%BD%20%D0%BA%D0%BB%D0%B8%D0%BA;%D0%98%D0%BC%D0%BF%D0%BE%D1%80%D1%82%20%D1%81%20%D0%BF%D1%80%D0%BE%D0%B2%D0%B5%D1%80%D0%BA%D0%BE%D0%B9%20%D1%84%D0%B0%D0%B9%D0%BB%D0%B0%20%D0%B8%20%D0%BE%D1%82%D0%BA%D0%B0%D1%82%D0%BE%D0%BC;%D0%90%D0%B2%D1%82%D0%BE%D0%B1%D1%8D%D0%BA%D0%B0%D0%BF%20%D0%BF%D0%BE%20%D1%80%D0%B0%D1%81%D0%BF%D0%B8%D1%81%D0%B0%D0%BD%D0%B8%D1%8E%20%D0%B2%20Telegram" alt="Возможности"/>
</a>

<p>
  <img src="https://skillicons.dev/icons?i=bash,docker,linux,ubuntu,postgres&theme=dark" alt="Bash · Docker · Linux · Ubuntu · PostgreSQL"/>
</p>

[![Version](https://img.shields.io/badge/version-2.1.1-0891b2?style=for-the-badge&labelColor=0d1117&logo=github)](VERSION)
[![Remnawave](https://img.shields.io/badge/Remnawave-3.4.11-2563eb?style=for-the-badge&labelColor=0d1117&logo=cloudflare&logoColor=white)](https://github.com/remnawave/backend)
[![Last Commit](https://img.shields.io/github/last-commit/CyberERROR/rw-back?style=for-the-badge&labelColor=0d1117&label=last%20commit&color=7c3aed)](https://github.com/CyberERROR/rw-back/commits)

[![Shell](https://img.shields.io/badge/bash-5%2B-4f46e5?style=flat-square&labelColor=0d1117&logo=gnubash&logoColor=white)](#requirements)
[![Telegram](https://img.shields.io/badge/Telegram-Bot%20API-2563eb?style=flat-square&labelColor=0d1117&logo=telegram&logoColor=white)](#bot)
[![License](https://img.shields.io/github/license/CyberERROR/rw-back?style=flat-square&labelColor=0d1117&label=license&color=0891b2)](LICENSE)
[![Issues](https://img.shields.io/github/issues/CyberERROR/rw-back?style=flat-square&labelColor=0d1117&label=issues&color=c026d3)](https://github.com/CyberERROR/rw-back/issues)

<br>

<table>
<tr>
<td align="center"><a href="#about"><b>📋<br>О проекте</b></a></td>
<td align="center"><a href="#features"><b>✨<br>Возможности</b></a></td>
<td align="center"><a href="#install"><b>🚀<br>Установка</b></a></td>
<td align="center"><a href="#bot"><b>🤖<br>Бот</b></a></td>
<td align="center"><a href="#backup"><b>💾<br>Бэкап</b></a></td>
<td align="center"><a href="#commands"><b>⌨️<br>Команды</b></a></td>
</tr>
</table>

</div>

<!-- ═══════════════════════════  ABOUT  ═══════════════════════════ -->
<a id="about"></a>

## 📋 О проекте

**rw-back** — резервное копирование **только базы данных** Remnawave: без nginx, без файлов, без мусора.
Живёт на том же сервере, что и панель, работает с её Docker-контейнером БД.

Состоит из двух файлов:

| Файл | Роль |
|---|---|
| [`install.sh`](install.sh) | установка, меню управления, обновление, служба бота, деинсталляция |
| [`rw-back-bot.sh`](rw-back-bot.sh) | Telegram-бот: кнопки экспорта и импорта, настройки, автобэкап |

<div align="center">

<img src="https://img.shields.io/badge/%D0%9F%D0%B0%D0%BD%D0%B5%D0%BB%D1%8C-0891b2?style=for-the-badge&labelColor=0d1117"/> ➜
<img src="https://img.shields.io/badge/%D0%94%D0%B0%D0%BC%D0%BF%20pg__dumpall-2563eb?style=for-the-badge&labelColor=0d1117"/> ➜
<img src="https://img.shields.io/badge/Telegram-7c3aed?style=for-the-badge&labelColor=0d1117"/> ➜
<img src="https://img.shields.io/badge/%D0%92%D0%BE%D1%81%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BB%D0%B5%D0%BD%D0%B8%D0%B5-c026d3?style=for-the-badge&labelColor=0d1117"/>

<sub>🛡 проверка файла · 💾 страховочный дамп · ⏸ пауза панели · ✅ health-проверка · ↩️ автооткат</sub>

</div>

<!-- ═══════════════════════════  FEATURES  ═══════════════════════════ -->
<a id="features"></a>

## ✨ Возможности

<table>
<tr>
<td width="50%" valign="top">

**💾 Бэкап**
- ✅ Дамп `pg_dumpall` из контейнера, одним файлом `.sql.gz`
- ✅ Ручной запуск и расписание (3 / 6 / 12 / 24 ч или своё)
- ✅ Отправка в Telegram — лично админам, не в общий чат
- ✅ Ротация: храните 2 / 5 / 10 или своё число архивов
- ✅ Уведомление о новой версии GitHub

</td>
<td width="50%" valign="top">

**📥 Импорт**
- ✅ Файл прямо в Telegram: `.sql`, `.sql.gz`, `.zip`
- ✅ Проверка файла до единой записи в базу
- ✅ Страховочный дамп перед восстановлением
- ✅ Панель на паузе, кэш valkey сбрасывается
- ✅ Не поднялась — автоматический откат

</td>
</tr>
</table>

<div align="center">

![Чистый bash](https://img.shields.io/badge/bash-без%20зависимостей-0891b2?style=flat-square&labelColor=0d1117)
![Только БД](https://img.shields.io/badge/только%20база-без%20nginx-2563eb?style=flat-square&labelColor=0d1117)
![systemd](https://img.shields.io/badge/systemd-автозапуск-4f46e5?style=flat-square&labelColor=0d1117)
![Откат](https://img.shields.io/badge/автооткат-при%20сбое-7c3aed?style=flat-square&labelColor=0d1117)

</div>

<!-- ═══════════════════════════  PREVIEW  ═══════════════════════════ -->
<a id="preview"></a>

## 🖼️ Как это выглядит

<details>
<summary><b>🤖 Бот: главное меню</b></summary>
<br>

```text
🗄 rw-back · v2.0.0
➖➖➖➖➖
💾 Бэкап базы Remnawave
🗓 Расписание: каждые 6 ч
📦 Хранить: 5 шт.
🔌 БД: запущена

   [ 💎 Remnawave ]  [ ⚙️ Настройки ]
```

</details>

<details>
<summary><b>💎 Бот: раздел Remnawave</b></summary>
<br>

```text
💎 Remnawave
➖➖➖➖➖
🗄 БД postgres: ✅ работает
💾 Размер: 128 MB
🖥 Панель: remnawave/backend:3.4.11

Экспорт — дамп файлом в чат.
Импорт — пришлёте дамп, восстановлю.

   [ 📤 Экспорт ]  [ 📥 Импорт ]
   [ 📦 Бэкапы на сервере ]
   [ ⬅️ Назад ]
```

</details>

<details>
<summary><b>⚙️ Бот: настройки</b></summary>
<br>

```text
⚙️ Настройки
➖➖➖➖➖
👥 Админов: 1
🕒 Расписание: каждые 6 ч
📦 Хранить файлов: 5

   [ 👥 Админы ]  [ 🕒 Расписание ]
   [ 📦 Хранить файлов ]
   [ ⬅️ Назад ]
```

Расписание и хранение — кнопками:

```text
[ 3 ч ] [ 6 ч ] [ 12 ч ]
[ 24 ч ] [ ✏️ Своё ]
[ ⏰ Выключить ]

[ 2 ] [ 5 ] [ 10 ]
[ ✏️ Своё значение ]
```

</details>

<details>
<summary><b>🖥️ Меню в консоли</b></summary>
<br>

```text
💎 RW-BACK  v2.0.0  (by CyberERROR)
──────────────────────────────────────────

🗄 БД: remnawave-db · архивов: 6
🕒 Автобэкап: каждые 6 ч (в боте)

1. 💾 Создать бэкап
2. 📥 Восстановить из архива
3. 📦 Список архивов

4. 🤖 Telegram-бот
5. 🛠  Параметры
6. 🔄 Проверить обновление

7. 🗑  Удалить rw-back
0. ❌ Выход
```

</details>

<!-- ═══════════════════════════  REQUIREMENTS  ═══════════════════════════ -->
<a id="requirements"></a>

## 📦 Что нужно

> [!NOTE]
> rw-back ставится **на тот же сервер**, где работает панель Remnawave.

| Компонент | Требование |
|---|---|
| 🐧 ОС | Ubuntu 20.04+ / Debian 11+ (или другой Linux с systemd) |
| 🔑 Доступ | SSH под `root` |
| 🐳 Docker | панель Remnawave **уже установлена и запущена** |
| 🗄 База | контейнер `remnawave-db` (Postgres из официального compose) |
| 💾 Диск | свободно ≥ 2× размера базы |
| 📱 Telegram | бот от [@BotFather](https://t.me/botfather), ID от [@userinfobot](https://t.me/userinfobot) |

Проверено на **Remnawave 3.4.11** (`remnawave-db`, PostgreSQL 18.4, valkey-кэш).

<!-- ═══════════════════════════  INSTALL  ═══════════════════════════ -->
<a id="install"></a>

<img src="https://capsule-render.vercel.app/api?type=soft&height=60&color=0:000000,55:030b1f,100:0891b2&text=%D0%A3%D0%A1%D0%A2%D0%90%D0%9D%D0%9E%D0%92%D0%9A%D0%90&fontSize=24&fontColor=22D3EE&fontAlignY=55&animation=fadeIn" width="100%" alt="УСТАНОВКА"/>

<img src="https://img.shields.io/badge/%D0%A8%D0%90%D0%93_1-%D0%9F%D0%BE%D0%B4%D0%BA%D0%BB%D1%8E%D1%87%D0%B8%D1%82%D0%B5%D1%81%D1%8C_%D0%BA_%D1%81%D0%B5%D1%80%D0%B2%D0%B5%D1%80%D1%83-0891b2?style=for-the-badge&labelColor=0d1117" alt="Шаг 1"/>

```bash
ssh root@your-server-ip
```

<img src="https://img.shields.io/badge/%D0%A8%D0%90%D0%93_2-%D0%97%D0%B0%D0%BF%D1%83%D1%81%D1%82%D0%B8%D1%82%D0%B5_%D1%83%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D1%89%D0%B8%D0%BA-2563eb?style=for-the-badge&labelColor=0d1117" alt="Шаг 2"/>

```bash
curl -sSL https://raw.githubusercontent.com/CyberERROR/rw-back/main/install.sh | bash
```

<img src="https://img.shields.io/badge/%D0%A8%D0%90%D0%93_3-%D0%9E%D1%82%D0%B2%D0%B5%D1%82%D1%8C%D1%82%D0%B5_%D0%BD%D0%B0_%D0%B2%D0%BE%D0%BF%D1%80%D0%BE%D1%81%D1%8B-7c3aed?style=for-the-badge&labelColor=0d1117" alt="Шаг 3"/>

| Вопрос | Пример | 💡 |
|:--|:--|:--|
| 🤖 Токен бота | `1234567:AA…` | [@BotFather](https://t.me/botfather) → `/newbot` |
| 🗄 Контейнер БД | `remnawave-db` | по умолчанию, менять не нужно |
| 📂 Каталог панели | `/opt/remnawave` | где лежит `docker-compose.yml` панели |
| 📦 Хранить файлов | `5` | ротация архивов |

<img src="https://img.shields.io/badge/%D0%A8%D0%90%D0%93_4-%D0%9F%D1%80%D0%B8%D0%B2%D1%8F%D0%B6%D0%B8%D1%82%D0%B5_%D0%B0%D0%B4%D0%BC%D0%B8%D0%BD%D0%B0-4f46e5?style=for-the-badge&labelColor=0d1117" alt="Шаг 4"/>

Установщик покажет **одноразовый 6-значный код**:

```text
══════════════════════════════════════════
🔑 КОД ПРИВЯЗКИ АДМИНА:  847213
══════════════════════════════════════════

1. Откройте бота:  https://t.me/your_bot
2. Напишите:       /start
3. Отправьте код:  847213
```

Откройте бота, отправьте `/start` и этот код в **личку**. Бот возьмёт ваш Telegram ID и запишет главным админом — дальше он слушает только вас, пока вы в **⚙️ Настройки → 👥 Админы** не добавите остальных.

> [!NOTE]
> Код живёт **30 минут** и сгорает после 10 неверных попыток. Новый: `rw-back admin-code`.

<img src="https://img.shields.io/badge/%D0%A8%D0%90%D0%93_5-%D0%93%D0%BE%D1%82%D0%BE%D0%B2%D0%BE-c026d3?style=for-the-badge&labelColor=0d1117" alt="Шаг 5"/>

```text
🎉 Установка завершена
Меню:        rw-back
Бот:         @ваш_бот → /start
Автозапуск:  systemctl status rw-back-bot
```

> [!TIP]
> Установщик сам ставит `curl`/`jq`/`unzip`, раскладывает файлы в `/opt/rw-back`, создаёт команду `rw-back` и поднимает службу бота.

<!-- ═══════════════════════════  BOT  ═══════════════════════════ -->
<a id="bot"></a>

<img src="https://capsule-render.vercel.app/api?type=soft&height=60&color=0:000000,55:030b1f,100:2563eb&text=TELEGRAM-%D0%91%D0%9E%D0%A2&fontSize=24&fontColor=60A5FA&fontAlignY=55&animation=fadeIn" width="100%" alt="TELEGRAM-БОТ"/>

Бот открывается командой **`/start`** и работает только для админов из списка.

<details>
<summary><b>🔑 Привязка главного админа</b> — одноразовый код при установке</summary>
<br>

1. Установщик генерирует **6-значный код** и показывает его в консоли
2. Вы открываете бота, отправляете `/start` и код **в личку**
3. Бот берёт ваш Telegram ID и записывает главным админом
4. Дальше он отвечает только вам, пока вы не добавите других в настройках

Защита:

- код живёт **30 минут**, хранится в `state/setup_code` с правами `600`
- только **личка** — в группе код не принимается
- **10 попыток**, затем код сгорает
- новый код: `rw-back admin-code`
</details>

| Раздел | Что внутри |
|---|---|
| 💎 **Remnawave** | 📤 Экспорт · 📥 Импорт · 📦 Бэкапы на сервере |
| ⚙️ **Настройки** | 👥 Админы · 🕒 Расписание · 📦 Сколько файлов хранить |

<details>
<summary><b>👥 Админы</b> — добавление по ID или @username</summary>
<br>

- `➕ Добавить` → пришлите `123456789` или `@username`
- `🗑 Удалить` → кнопка со списком
- последнего админа удалить нельзя — иначе бот станет неуправляемым

> [!IMPORTANT]
> Экспорт, импорт и настройки доступны **только админам**. Остальным бот не отвечает.
</details>

<details>
<summary><b>🕒 Расписание</b> — автобэкап по часам</summary>
<br>

Кнопки `3 / 6 / 12 / 24 ч` или `✏️ Своё` (1–168 часов). Дамп приходит **в личку каждому админу** — в группу файлы с персональными данными не отправляются.

Выключить: `⏰ Выключить`.

Под капотом — обычная cron-задача `rw-back-bot.sh cron`.
</details>

<details>
<summary><b>📦 Хранение</b> — сколько архивов оставлять</summary>
<br>

Кнопки `2 / 5 / 10` или `✏️ Своё значение` (1–200). После каждого бэкапа лишние архивы удаляются автоматически, страховочные дампы перед импортом — не больше трёх.
</details>

<!-- ═══════════════════════════  BACKUP  ═══════════════════════════ -->
<a id="backup"></a>

<img src="https://capsule-render.vercel.app/api?type=soft&height=60&color=0:000000,55:030b1f,100:4f46e5&text=%D0%AD%D0%9A%D0%A1%D0%9F%D0%9E%D0%A0%D0%A2%20%D0%B8%20%D0%98%D0%9C%D0%9F%D0%9E%D0%A0%D0%A2&fontSize=22&fontColor=818CF8&fontAlignY=55&animation=fadeIn" width="100%" alt="ЭКСПОРТ и ИМПОРТ"/>

### 📤 Экспорт

`Remnawave → 📤 Экспорт` — бот делает `pg_dumpall -c` из контейнера, сжимает gzip и присылает файл.

### 📥 Импорт

`Remnawave → 📥 Импорт` → пришлите файл → бот покажет отчёт о проверке → **`✅ Восстановить`**.

Что происходит по шагам:

| # | Действие |
|:-:|---|
| 1 | Повторная проверка файла (он мог измениться на диске) |
| 2 | Страховочный дамп текущей БД → `backup/pre_restore/` |
| 3 | Панель **останавливается** |
| 4 | `psql` заливает дамп в контейнер БД |
| 5 | Сбрасывается кэш valkey (иначе панель покажет старые данные) |
| 6 | Панель поднимается, ждём `healthy` до 3 минут |
| 7 | Не поднялась → **автоматический откат** страховочным дампом |

### 🔒 Что проверяется в файле

> [!CAUTION]
> Дамп исполняется в PostgreSQL от суперпользователя. Поэтому файл проверяется **до** записи в базу.

| Проверка | Что ловим |
|---|---|
| Магия файла | gzip / zip / обычный SQL; битые и пустые файлы |
| Заголовок | `PostgreSQL database dump` — иначе это не дамп |
| Таблицы Remnawave | обязательна `users`, нужны ещё минимум две (`nodes`, `hosts`, `config_profiles`, `admin`, …) |
| Данные | наличие `COPY` или `INSERT` — пустышка не пройдёт |
| Мета-команды `psql` | всё, кроме `\connect` (только к своей БД), `\restrict`, `\unrestrict`, `\.`, `\N` |
| Опасные конструкции | `COPY … PROGRAM`, `COPY … TO 'файл'`, `ALTER SYSTEM`, `CREATE EXTENSION`, `SUPERUSER`, `pg_read_file` / `lo_import` / `dblink` |
| zip | ровно один файл, без `../` и абсолютных путей, только `.sql`/`.sql.gz`, защита от «бомбы» |
| Данные COPY | строки внутри `COPY … \.` не считаются командами — ложных срабатываний нет |

### 📉 Лимиты Telegram

> [!IMPORTANT]
> Bot API: бот **скачивает** файлы до **20 МБ**, **отправляет** до **50 МБ**.

Если файл больше — бот пришлёт пошаговую инструкцию:

1. `ssh root@ВАШ_IP`
2. `docker ps | grep remnawave`
3. `mkdir -p /opt/rw-back/backup` + `scp backup.sql.gz root@IP:/opt/rw-back/backup/`
4. `rw-back validate /opt/rw-back/backup/backup.sql.gz`
5. `rw-back restore /opt/rw-back/backup/backup.sql.gz`
6. или меню: `rw-back` → «Восстановить из архива»

<!-- ═══════════════════════════  COMMANDS  ═══════════════════════════ -->
<a id="commands"></a>

<img src="https://capsule-render.vercel.app/api?type=soft&height=60&color=0:000000,55:030b1f,100:7c3aed&text=%D0%9A%D0%9E%D0%9C%D0%90%D0%9D%D0%94%D0%AB&fontSize=24&fontColor=A78BFA&fontAlignY=55&animation=fadeIn" width="100%" alt="КОМАНДЫ"/>

| Команда | Что делает |
|---|---|
| `rw-back` | открыть меню |
| `rw-back backup` | бэкап без меню + отправка админам |
| `rw-back restore ФАЙЛ` | восстановить БД из файла |
| `rw-back validate ФАЙЛ` | проверить дамп, ничего не меняя |
| `rw-back list` | список архивов |
| `rw-back update` | обновить до последней версии |
| `rw-back admin-code` | новый код привязки главного админа |
| `rw-back bot-install` | поставить/перезапустить службу бота |
| `rw-back version` | текущая версия |
| `rw-back remove` | полностью удалить (архивы можно сохранить) |

<details>
<summary><b>🗂 Где что лежит</b></summary>
<br>

```text
/opt/rw-back/
├── install.sh          установщик и меню
├── rw-back-bot.sh      бот
├── VERSION             версия
├── config.env          настройки (chmod 600)
├── backup/             архивы rw_db_backup_*.sql.gz
│   └── pre_restore/    страховочные дампы перед импортом
├── state/              offset бота, входящие файлы, кэш обновлений
├── logs/               логи cron
└── scripts/            резервные копии файлов при обновлении
```

</details>

<details>
<summary><b>♻️ Служба бота</b></summary>
<br>

```bash
systemctl status rw-back-bot      # состояние
systemctl restart rw-back-bot     # перезапуск
journalctl -u rw-back-bot -f      # логи
```

</details>

<!-- ═══════════════════════════  UPDATE  ═══════════════════════════ -->
<a id="update"></a>

<img src="https://capsule-render.vercel.app/api?type=soft&height=60&color=0:000000,55:030b1f,100:c026d3&text=%D0%9E%D0%91%D0%9D%D0%9E%D0%92%D0%9B%D0%95%D0%9D%D0%98%D0%95&fontSize=24&fontColor=E879F9&fontAlignY=55&animation=fadeIn" width="100%" alt="ОБНОВЛЕНИЕ"/>

```bash
rw-back update
```

Порядок безопасный: скачивание в `/tmp` → `bash -n` обоих файлов → копия текущих в `scripts/` → замена → перезапуск службы.
Если новый файл не проходит проверку синтаксиса — обновление отменяется, старое остаётся.

> [!TIP]
> Бот сам проверяет GitHub (кэш 6 часов) и показывает в сообщениях «⬆️ Доступно обновление».

<!-- ═══════════════════════════  FAQ  ═══════════════════════════ -->
<a id="faq"></a>

## ❓ Частые вопросы

<details>
<summary><b>Бот молчит</b></summary>
<br>

1. `systemctl status rw-back-bot`
2. `journalctl -u rw-back-bot -n 50`
3. Проверьте, что ваш ID есть в админах: меню → 5 → 4 или `grep BOT_ADMIN_IDS /opt/rw-back/config.env`

</details>

<details>
<summary><b>«Контейнер БД не запущен»</b></summary>
<br>

```bash
cd /opt/remnawave && docker compose up -d remnawave-db
docker ps | grep remnawave-db
```

</details>

<details>
<summary><b>Импорт не прошёл, что с базой?</b></summary>
<br>

Смотрите сообщение бота: если написано «Откат: да» — база восстановлена из страховочного дампа.
Логи: `docker logs --tail 100 remnawave` и последний `restore_*.log` в `/opt/rw-back/state/`.

</details>

<details>
<summary><b>Дамп большой, Telegram не берёт</b></summary>
<br>

Это лимиты Bot API (20 МБ на скачивание, 50 МБ на отправку). Используйте `scp` + шаги из [инструкции](#backup).

</details>

<details>
<summary><b>Можно перенести панель на другой сервер?</b></summary>
<br>

Да: на новом сервере поставьте rw-back и восстановите дамп. Дальше поднимите панель официальным `docker compose` и проверьте, что домен смотрит на новый IP.

</details>

<a id="tests"></a>

## 🧪 Тесты

```bash
bash tests/test_validate.sh   # 13 кейсов валидатора дампов
bash tests/test_bot.sh        # 35 кейсов логики бота
```

Нужны только `bash` и `jq` — Docker, сеть и Telegram не требуются. Подробности в [tests/README.md](tests/README.md).

<!-- ═══════════════════════════  SECURITY  ═══════════════════════════ -->
## 🛡 Безопасность

- 🔑 `config.env` — `chmod 600`, каталоги — `700`
- 👥 операции только для админов, чужие сообщения игнорируются
- 🎟 первый админ привязывается одноразовым кодом: 6 цифр, 30 минут, 10 попыток, только в личке
- 🔒 одновременные операции блокируются (`flock`)
- 📥 входящие файлы проверяются до восстановления, `../` и абсолютные пути в zip отсекаются
- 🧯 перед импортом — страховочный дамп; при сбое панель откатывается
- 🚫 дампы не публикуются в групповые чаты
- 📊 перед операциями проверяется свободное место

<!-- ═══════════════════════════  FOOTER  ═══════════════════════════ -->

## 📄 Лицензия

Распространяется по лицензии **[GPLv3](LICENSE)**.

<div align="center">

<br>

[![Issues](https://img.shields.io/badge/Нашли_баг-сообщите-2563eb?style=for-the-badge&labelColor=0d1117&logo=github&logoColor=white)](https://github.com/CyberERROR/rw-back/issues/new)
[![Star](https://img.shields.io/badge/Поставить_звезду-c026d3?style=for-the-badge&labelColor=0d1117&logo=github&logoColor=white)](https://github.com/CyberERROR/rw-back)

**Сделано с ❤️ для сообщества** · <a href="#about">⬆️ Наверх</a>

<img src="https://capsule-render.vercel.app/api?type=waving&height=130&section=footer&color=0:0a1a3f,60:030b1f,100:000000" width="100%"/>

</div>

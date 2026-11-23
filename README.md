<a id="top"></a>

<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&height=210&section=header&color=0:000000,40:030b1f,100:0a1a3f&text=RW-BACK&fontSize=64&fontColor=22D3EE&fontAlignY=36&desc=%D0%91%D1%8D%D0%BA%D0%B0%D0%BF%20%D0%91%D0%94%20Remnawave%20%2B%20Telegram-%D0%B1%D0%BE%D1%82&descSize=17&descAlignY=60&animation=fadeIn" width="100%" alt="rw-back"/>

[![Version](https://img.shields.io/badge/version-2.1.2-0891b2?style=for-the-badge&labelColor=0d1117&logo=github)](VERSION)
[![Remnawave](https://img.shields.io/badge/Remnawave-3.4.11-2563eb?style=for-the-badge&labelColor=0d1117)](https://github.com/remnawave/backend)
[![License](https://img.shields.io/github/license/CyberERROR/rw-back?style=for-the-badge&labelColor=0d1117&label=license&color=4f46e5)](LICENSE)

<sub>Быстрый переход</sub>

[![Установка](https://img.shields.io/badge/%D0%A3%D1%81%D1%82%D0%B0%D0%BD%D0%BE%D0%B2%D0%BA%D0%B0-0891b2?style=for-the-badge&labelColor=0d1117)](#install)
[![Бот](https://img.shields.io/badge/%D0%91%D0%BE%D1%82-2563eb?style=for-the-badge&labelColor=0d1117)](#bot)
[![Импорт](https://img.shields.io/badge/%D0%98%D0%BC%D0%BF%D0%BE%D1%80%D1%82-4f46e5?style=for-the-badge&labelColor=0d1117)](#import)
[![Команды](https://img.shields.io/badge/%D0%9A%D0%BE%D0%BC%D0%B0%D0%BD%D0%B4%D1%8B-7c3aed?style=for-the-badge&labelColor=0d1117)](#commands)

[![Что это](https://img.shields.io/badge/%D0%A7%D1%82%D0%BE%20%D1%8D%D1%82%D0%BE-334155?style=for-the-badge&labelColor=0d1117)](#what)
[![Возможности](https://img.shields.io/badge/%D0%92%D0%BE%D0%B7%D0%BC%D0%BE%D0%B6%D0%BD%D0%BE%D1%81%D1%82%D0%B8-334155?style=for-the-badge&labelColor=0d1117)](#features)
[![Безопасность](https://img.shields.io/badge/%D0%91%D0%B5%D0%B7%D0%BE%D0%BF%D0%B0%D1%81%D0%BD%D0%BE%D1%81%D1%82%D1%8C-334155?style=for-the-badge&labelColor=0d1117)](#security)
[![Файлы](https://img.shields.io/badge/%D0%A4%D0%B0%D0%B9%D0%BB%D1%8B-334155?style=for-the-badge&labelColor=0d1117)](#files)

</div>

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/divider-dark.svg"><img src="assets/divider.svg" width="100%" alt=""></picture>

<a id="what"></a>

## 📋 Что это

Бэкап **только базы** Remnawave — без nginx и файлов. Живёт на том же сервере, что панель.

| Файл | Роль |
|---|---|
| [`install.sh`](install.sh) | установка, меню, служба, обновление, удаление |
| [`rw-back-bot.sh`](rw-back-bot.sh) | бот: экспорт/импорт, настройки, автобэкап |

<div align="center"><img src="https://skillicons.dev/icons?i=bash,docker,linux,postgres&theme=dark" height="38" alt="bash · docker · linux · postgres"/></div>

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/divider-dark.svg"><img src="assets/divider.svg" width="100%" alt=""></picture>

<a id="features"></a>

## ✨ Возможности

- 💾 дамп `pg_dumpall` в `.sql.gz`, отправка в Telegram
- ⏰ автобэкап каждые 3/6/12/24 ч или своё
- 📦 хранение 2/5/10 архивов или своё число
- 📥 импорт из `.sql`, `.sql.gz`, `.zip` с проверкой файла
- 🛡 страховочный дамп, пауза панели, автооткат при сбое
- ⬆️ проверка новой версии через GitHub

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/divider-dark.svg"><img src="assets/divider.svg" width="100%" alt=""></picture>

<a id="install"></a>

## 🚀 Установка

```bash
ssh root@your-server-ip
curl -sSL https://raw.githubusercontent.com/CyberERROR/rw-back/main/install.sh | bash
```

Установщик спросит токен бота и покажет **код привязки**:

```text
🔑 КОД ПРИВЯЗКИ АДМИНА:  847213
1. https://t.me/your_bot
2. /start
3. 847213
```

Отправьте код боту **в личку** — он запишет ваш Telegram ID главным админом.
Код живёт 30 минут, 10 попыток. Новый: `rw-back admin-code`.

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/divider-dark.svg"><img src="assets/divider.svg" width="100%" alt=""></picture>

<a id="bot"></a>

## 🤖 Бот

`/start` → два раздела:

| Раздел | Что внутри |
|---|---|
| 💎 **Remnawave** | 📤 Экспорт · 📥 Импорт · 📦 Бэкапы на сервере |
| ⚙️ **Настройки** | 👥 Админы · 🕒 Расписание · 📦 Хранить файлов |

Админы добавляются по `ID` или `@username`; последнего удалить нельзя.
Экспорт и импорт доступны только админам, дампы — только в личку.

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/divider-dark.svg"><img src="assets/divider.svg" width="100%" alt=""></picture>

<a id="import"></a>

## 📥 Импорт

1. Проверка файла: заголовок pg_dump, таблицы Remnawave, опасные команды
2. Страховочный дамп текущей БД
3. Пауза панели → восстановление → сброс кэша valkey
4. Запуск панели и ожидание `healthy`
5. Не поднялась — откат страховочным дампом

Лимиты Telegram: **20 МБ** на скачивание, **50 МБ** на отправку. Если файл больше — бот пришлёт пошаговую инструкцию (`scp` → `rw-back validate` → `rw-back restore`).

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/divider-dark.svg"><img src="assets/divider.svg" width="100%" alt=""></picture>

<a id="commands"></a>

## ⌨️ Команды

| Команда | Что делает |
|---|---|
| `rw-back` | меню |
| `rw-back backup` | бэкап + отправка админам |
| `rw-back restore ФАЙЛ` | восстановить БД |
| `rw-back validate ФАЙЛ` | проверить дамп |
| `rw-back list` | список архивов |
| `rw-back update` | обновить |
| `rw-back admin-code` | новый код привязки |
| `rw-back remove` | удалить |

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/divider-dark.svg"><img src="assets/divider.svg" width="100%" alt=""></picture>

<a id="security"></a>

## 🛡 Безопасность

- `config.env` — `600`, каталоги — `700`
- только админы, чужие сообщения игнорируются
- первый админ — одноразовый код (30 минут, личка, 10 попыток)
- параллельные операции блокируются (`flock`)
- дампы не публикуются в группы

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/divider-dark.svg"><img src="assets/divider.svg" width="100%" alt=""></picture>

<a id="files"></a>

## 🗂 Файлы

```text
/opt/rw-back/
├── install.sh · rw-back-bot.sh · VERSION
├── config.env          настройки (600)
├── backup/             архивы, pre_restore/
├── state/              код привязки, входящие файлы
└── logs/
```

<picture><source media="(prefers-color-scheme: dark)" srcset="assets/divider-dark.svg"><img src="assets/divider.svg" width="100%" alt=""></picture>

## 📄 Лицензия

[GPLv3](LICENSE)

<div align="center">

[![Issues](https://img.shields.io/badge/%D0%9D%D0%B0%D1%88%D0%BB%D0%B8%20%D0%B1%D0%B0%D0%B3-%D1%81%D0%BE%D0%BE%D0%B1%D1%89%D0%B8%D1%82%D0%B5-2563eb?style=for-the-badge&labelColor=0d1117&logo=github&logoColor=white)](https://github.com/CyberERROR/rw-back/issues/new)
[![Star](https://img.shields.io/badge/%D0%9F%D0%BE%D1%81%D1%82%D0%B0%D0%B2%D0%B8%D1%82%D1%8C%20%D0%B7%D0%B2%D0%B5%D0%B7%D0%B4%D1%83-c026d3?style=for-the-badge&labelColor=0d1117&logo=github&logoColor=white)](https://github.com/CyberERROR/rw-back)

<a href="#top">⬆️ Наверх</a>

<img src="https://capsule-render.vercel.app/api?type=waving&height=100&section=footer&color=0:0a1a3f,60:030b1f,100:000000" width="100%" alt=""/>

</div>

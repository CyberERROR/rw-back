<!-- ═══════════════════════════  HEADER  ═══════════════════════════ -->
<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&height=230&section=header&color=0:000000,40:030b1f,100:0a1a3f&text=RW-BACK&fontSize=70&fontColor=22D3EE&fontAlignY=38&desc=%D0%91%D1%8D%D0%BA%D0%B0%D0%BF%20%D0%91%D0%94%20Remnawave%20%2B%20Telegram-%D0%B1%D0%BE%D1%82&descSize=18&descAlignY=62&animation=fadeIn" width="100%" alt="rw-back"/>

[![Version](https://img.shields.io/badge/version-2.1.2-0891b2?style=for-the-badge&labelColor=0d1117&logo=github)](VERSION)
[![Remnawave](https://img.shields.io/badge/Remnawave-3.4.11-2563eb?style=for-the-badge&labelColor=0d1117)](https://github.com/remnawave/backend)
[![License](https://img.shields.io/github/license/CyberERROR/rw-back?style=for-the-badge&labelColor=0d1117&label=license&color=4f46e5)](LICENSE)

[![Shell](https://img.shields.io/badge/bash-5%2B-4f46e5?style=flat-square&labelColor=0d1117&logo=gnubash&logoColor=white)](#install)
[![Telegram](https://img.shields.io/badge/Telegram-Bot%20API-2563eb?style=flat-square&labelColor=0d1117&logo=telegram&logoColor=white)](#bot)
[![Issues](https://img.shields.io/github/issues/CyberERROR/rw-back?style=flat-square&labelColor=0d1117&label=issues&color=c026d3)](https://github.com/CyberERROR/rw-back/issues)

</div>

## 📋 Что это

Бэкап **только базы** Remnawave — без nginx и файлов. Живёт на том же сервере, что панель.

| Файл | Роль |
|---|---|
| [`install.sh`](install.sh) | установка, меню, служба, обновление, удаление |
| [`rw-back-bot.sh`](rw-back-bot.sh) | бот: экспорт/импорт, настройки, автобэкап |

## ✨ Возможности

- 💾 дамп `pg_dumpall` в `.sql.gz`, отправка в Telegram
- ⏰ автобэкап каждые 3/6/12/24 ч или своё
- 📦 хранение 2/5/10 архивов или своё число
- 📥 импорт из `.sql`, `.sql.gz`, `.zip` с проверкой файла
- 🛡 страховочный дамп, пауза панели, автооткат при сбое
- ⬆️ проверка новой версии через GitHub

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

## 🤖 Бот

`/start` → два раздела:

| Раздел | Что внутри |
|---|---|
| 💎 **Remnawave** | 📤 Экспорт · 📥 Импорт · 📦 Бэкапы на сервере |
| ⚙️ **Настройки** | 👥 Админы · 🕒 Расписание · 📦 Хранить файлов |

Админы добавляются по `ID` или `@username`; последнего удалить нельзя.
Экспорт и импорт доступны только админам, дампы — только в личку.

## 📥 Импорт

1. Проверка файла: заголовок pg_dump, таблицы Remnawave, опасные команды
2. Страховочный дамп текущей БД
3. Пауза панели → восстановление → сброс кэша valkey
4. Запуск панели и ожидание `healthy`
5. Не поднялась — откат страховочным дампом

Лимиты Telegram: **20 МБ** на скачивание, **50 МБ** на отправку. Если файл больше — бот пришлёт пошаговую инструкцию (`scp` → `rw-back validate` → `rw-back restore`).

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

## 🛡 Безопасность

- `config.env` — `600`, каталоги — `700`
- только админы, чужие сообщения игнорируются
- первый админ — одноразовый код (30 минут, личка, 10 попыток)
- параллельные операции блокируются (`flock`)
- дампы не публикуются в группы

## 🗂 Файлы

```text
/opt/rw-back/
├── install.sh · rw-back-bot.sh · VERSION
├── config.env          настройки (600)
├── backup/             архивы, pre_restore/
├── state/              код привязки, входящие файлы
└── logs/
```

## 📄 Лицензия

[GPLv3](LICENSE)

<div align="center">

[![Issues](https://img.shields.io/badge/Нашли_баг-сообщите-2563eb?style=for-the-badge&labelColor=0d1117&logo=github&logoColor=white)](https://github.com/CyberERROR/rw-back/issues/new)
[![Star](https://img.shields.io/badge/Поставить_звезду-c026d3?style=for-the-badge&labelColor=0d1117&logo=github&logoColor=white)](https://github.com/CyberERROR/rw-back)

<img src="https://capsule-render.vercel.app/api?type=waving&height=110&section=footer&color=0:0a1a3f,60:030b1f,100:000000" width="100%"/>

</div>

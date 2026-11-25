<div align="center">

# 💎 RW-BACK

**Резервное копирование базы Remnawave — одной кнопкой, с доставкой в Telegram**

[![version](https://img.shields.io/badge/version-2.2.10-0891b2?style=for-the-badge&labelColor=0d1117&logo=github)](../VERSION)
[![Remnawave](https://img.shields.io/badge/Remnawave-3.4.11-2563eb?style=for-the-badge&labelColor=0d1117)](https://github.com/remnawave/backend)
[![bash](https://img.shields.io/badge/bash-5%2B-0891b2?style=for-the-badge&labelColor=0d1117&logo=gnubash&logoColor=white)](../install.sh)
[![license](https://img.shields.io/badge/license-GPLv3-4f46e5?style=for-the-badge&labelColor=0d1117)](../LICENSE)

🐳 **Remnawave** ➜ `pg_dumpall` ➜ 📤 **Telegram** ➜ 📥 **Восстановление**

</div>

## 📸 Скриншоты

<div align="center">

**🖥 Меню в консоли**

<img src="../img/cli-menu.png" width="460" alt="Меню rw-back в консоли">

</div>

<details>
<summary><b>📱 Скриншоты бота — 4 шт.</b></summary>

<br>

| <img src="../img/bot-menu.png" width="340" alt="Главный экран бота"><br><sub><b>01</b> · 🤖 Главный экран</sub> | <img src="../img/bot-backup.png" width="340" alt="Бэкап в чате"><br><sub><b>02</b> · 💾 Бэкап в чате</sub> |
|:--:|:--:|
| <img src="../img/bot-remnawave.png" width="340" alt="Экспорт и импорт"><br><sub><b>03</b> · 📤 Экспорт и импорт</sub> | <img src="../img/bot-settings.png" width="340" alt="Настройки"><br><sub><b>04</b> · ⚙️ Настройки</sub> |

</details>

## ✨ Что нового в 2.2.10

- 🔧 уходит от «битого архива»: дамп пишется целиком, проверяется финальная метка `pg_dumpall`, и только потом сжимается
- 🔁 повтор дампа через 15 секунд — разовый сбой записи больше не съедает бэкап
- ⏱ тик перенесён на `:17` — вне пика задач, стартующих в начале часа
- 🗄 битый дамп не удаляется, а уходит в карантин `state/corrupt/` — можно вскрыть и увидеть место обрыва
- 💾 проверка свободного места перед дампом и в сообщении о сбое
- ❌ причины стали точнее: код возврата и текст ошибки `pg_dumpall`, обрыв дампа, мало места

## 🚀 Установка

```bash
curl -sSL https://raw.githubusercontent.com/CyberERROR/rw-back/main/install.sh | bash
```

## 🔄 Обновление

```bash
sudo rw-back update
```

## 📄 Лицензия

Распространяется по лицензии **[GPLv3](../LICENSE)**.

<div align="center">

**CyberERROR** · [github.com/CyberERROR/rw-back](https://github.com/CyberERROR/rw-back)

</div>

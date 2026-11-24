<div align="center">

# 💎 RW-BACK

**Резервное копирование базы Remnawave — одной кнопкой, с доставкой в Telegram**

[![version](https://img.shields.io/badge/version-2.2.9-0891b2?style=for-the-badge&labelColor=0d1117&logo=github)](../VERSION)
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

## ✨ Что нового в 2.2.9

- 🔔 автобэкап больше не молчит: при сбое приходит сообщение с причиной
- 🩺 точные причины вместо «pg_dumpall вернул ошибку»: нет контейнера БД · пустой дамп · обрыв соединения · файл не доставлен
- 📅 статус в боте: последний бэкап, следующий запуск, последняя ошибка
- 🔁 неудачная попытка тоже фиксируется — каскада запусков каждые 5 минут нет
- ✋ `rw-back cron --force` — прогон вручную, расписание не сдвигается
- ⏱ запас 5 минут: тик, пришедший на секунду раньше, больше не съедает час
- 🖥 в консольном меню видно «след. 10:00» или «⚠ сбой · причина»

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

#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  install.sh — установка и управление rw-back
#  Бэкап базы Remnawave + Telegram-бот (импорт/экспорт)
#  Репозиторий: https://github.com/CyberERROR/rw-back
# ───────────────────────────────────────────────────────────────────────────
#  Быстрый старт:
#    curl -sSL https://raw.githubusercontent.com/CyberERROR/rw-back/main/install.sh | bash
#  После установки:
#    rw-back              — меню
#    rw-back backup       — бэкап без меню
#    rw-back restore ФАЙЛ — восстановление
#    rw-back update       — обновление
#    rw-back remove       — удаление
# ═══════════════════════════════════════════════════════════════════════════
set -o pipefail

# ── Цвета ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; CYAN=$'\e[36m'
    MAGENTA=$'\e[35m'; GRAY=$'\e[90m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; MAGENTA=""; GRAY=""; BOLD=""; RESET=""
fi

# ── Пути ────────────────────────────────────────────────────────────────────
SELF_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"
SELF_DIR="$(dirname "$SELF_PATH")"
# При запуске через `curl | bash` в $0 оказывается интерпретатор (например /usr/bin/bash),
# поэтому «мы — файл скрипта» проверяем по содержимому, а не только по пути.
SELF_IS_SCRIPT=false
if [[ -f "$SELF_PATH" ]] && head -c 2 "$SELF_PATH" 2>/dev/null | grep -q '#!' \
    && grep -q 'rw-back' "$SELF_PATH" 2>/dev/null; then
    SELF_IS_SCRIPT=true
fi
INSTALL_DIR="/opt/rw-back"
BOT_SCRIPT="$INSTALL_DIR/rw-back-bot.sh"
BACKUP_DIR="$INSTALL_DIR/backup"
STATE_DIR="$INSTALL_DIR/state"
LOG_DIR="$INSTALL_DIR/logs"
CONFIG_FILE="$INSTALL_DIR/config.env"
VERSION_FILE="$INSTALL_DIR/VERSION"
SYMLINK_PATH="/usr/local/bin/rw-back"
SERVICE_NAME="rw-back-bot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
REPO="CyberERROR/rw-back"
REPO_API="https://api.github.com/repos/$REPO"
RAW_MAIN="https://raw.githubusercontent.com/$REPO/main"
UPDATE_CACHE_TTL=21600

# ── Печать ──────────────────────────────────────────────────────────────────
print_message() {
    local type="$1" message="$2" color="$RESET"
    case "$type" in
        SUCCESS) color="$GREEN" ;;
        WARN) color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        ACTION) color="$CYAN" ;;
        INFO) color="$GRAY" ;;
    esac
    printf '%s[%s]%s %s\n' "$color" "$type" "$RESET" "$message"
}

die() {
    print_message "ERROR" "$*"
    exit 1
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        die "Нужны права root: sudo bash $0"
    fi
}

# ── Конфиг (общий с ботом) ──────────────────────────────────────────────────
load_config() {
    BOT_TOKEN=""; CHAT_ID=""; BOT_ADMIN_IDS=""
    DB_USER="postgres"; DB_NAME="postgres"; DB_CONTAINER="remnawave-db"
    PANEL_CONTAINER="remnawave"; CACHE_CONTAINER="remnawave-redis"
    CRON_HOURS="0"; KEEP_FILES="5"; PANEL_DIR="/opt/remnawave"

    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi

    DB_USER=${DB_USER:-postgres}
    DB_NAME=${DB_NAME:-postgres}
    DB_CONTAINER=${DB_CONTAINER:-remnawave-db}
    PANEL_CONTAINER=${PANEL_CONTAINER:-remnawave}
    CACHE_CONTAINER=${CACHE_CONTAINER:-remnawave-redis}
    PANEL_DIR=${PANEL_DIR:-/opt/remnawave}
    CRON_HOURS=${CRON_HOURS:-0}
    KEEP_FILES=${KEEP_FILES:-5}
    BOT_ADMIN_IDS=${BOT_ADMIN_IDS:-}
}

save_config() {
    mkdir -p "$INSTALL_DIR" || return 1
    local tmp="$CONFIG_FILE.tmp.$$"
    umask 077
    {
        printf 'BOT_TOKEN=%q\n' "$BOT_TOKEN"
        printf 'CHAT_ID=%q\n' "$CHAT_ID"
        printf 'BOT_ADMIN_IDS=%q\n' "$BOT_ADMIN_IDS"
        printf 'DB_USER=%q\n' "$DB_USER"
        printf 'DB_NAME=%q\n' "$DB_NAME"
        printf 'DB_CONTAINER=%q\n' "$DB_CONTAINER"
        printf 'PANEL_CONTAINER=%q\n' "$PANEL_CONTAINER"
        printf 'CACHE_CONTAINER=%q\n' "$CACHE_CONTAINER"
        printf 'CRON_HOURS=%q\n' "$CRON_HOURS"
        printf 'KEEP_FILES=%q\n' "$KEEP_FILES"
        printf 'PANEL_DIR=%q\n' "$PANEL_DIR"
    } > "$tmp" || return 1
    chmod 600 "$tmp" 2>/dev/null
    mv -f "$tmp" "$CONFIG_FILE"
}

local_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        head -n 1 "$VERSION_FILE" | tr -d '[:space:]'
    elif [[ -f "$SELF_DIR/VERSION" ]]; then
        head -n 1 "$SELF_DIR/VERSION" | tr -d '[:space:]'
    else
        echo "dev"
    fi
}

# ── Зависимости ─────────────────────────────────────────────────────────────
install_deps() {
    local need=(curl jq gzip cron)
    local missing=() p
    for p in "${need[@]}"; do
        command -v "$p" > /dev/null 2>&1 || missing+=("$p")
    done
    # cron на Debian/Ubuntu живёт как cron/cronie
    if ! command -v crontab > /dev/null 2>&1; then
        missing+=("cron")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_message "INFO" "Устанавливаю пакеты: ${missing[*]}"
        if command -v apt-get > /dev/null 2>&1; then
            apt-get update -qq > /dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" > /dev/null 2>&1 || true
        elif command -v dnf > /dev/null 2>&1; then
            dnf install -y "${missing[@]}" > /dev/null 2>&1 || true
        elif command -v yum > /dev/null 2>&1; then
            yum install -y "${missing[@]}" > /dev/null 2>&1 || true
        fi
    fi

    for p in curl jq gzip; do
        command -v "$p" > /dev/null 2>&1 || die "Не установлен $p"
    done
}

# ── Скачивание файлов проекта ───────────────────────────────────────────────
fetch_file() { # url dest [marker]
    local url="$1" dest="$2" marker="${3:-}"
    local tmp="$dest.tmp.$$"

    if ! curl -fsSL --max-time 60 -H "User-Agent: rw-back-installer" -o "$tmp" "$url"; then
        rm -f "$tmp"
        return 1
    fi
    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        return 1
    fi
    if [[ -n "$marker" ]] && ! grep -q "$marker" "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$dest"
    return 0
}

install_self() {
    print_message "INFO" "Раскладываю файлы в ${BOLD}${INSTALL_DIR}${RESET}…"
    mkdir -p "$INSTALL_DIR" "$BACKUP_DIR" "$STATE_DIR" "$LOG_DIR" "$INSTALL_DIR/scripts"

    # install.sh: если запущены из файла — копируем, иначе (curl | bash) скачиваем
    if [[ "$SELF_IS_SCRIPT" == true && "$SELF_PATH" != "$INSTALL_DIR/install.sh" ]]; then
        cp -f "$SELF_PATH" "$INSTALL_DIR/install.sh" || die "Не удалось скопировать установщик"
    elif [[ ! -s "$INSTALL_DIR/install.sh" ]]; then
        print_message "INFO" "Скачиваю install.sh из GitHub…"
        fetch_file "$RAW_MAIN/install.sh" "$INSTALL_DIR/install.sh" "rw-back" ||
            die "Не удалось скачать install.sh"
    fi
    chmod 755 "$INSTALL_DIR/install.sh"

    # rw-back-bot.sh: сначала локальный, затем из репозитория
    local bot_src=""
    if [[ "$SELF_IS_SCRIPT" == true && -f "$SELF_DIR/rw-back-bot.sh" ]]; then
        bot_src="$SELF_DIR/rw-back-bot.sh"
    elif [[ -f "$BOT_SCRIPT" ]]; then
        bot_src="$BOT_SCRIPT"
    fi

    if [[ -n "$bot_src" ]]; then
        if [[ "$bot_src" != "$BOT_SCRIPT" ]]; then
            cp -f "$bot_src" "$BOT_SCRIPT" || die "Не удалось скопировать бота"
        fi
        print_message "SUCCESS" "Бот установлен из локальной папки"
    else
        print_message "INFO" "Скачиваю rw-back-bot.sh из GitHub…"
        fetch_file "$RAW_MAIN/rw-back-bot.sh" "$BOT_SCRIPT" "rw-back-bot" ||
            die "Не удалось скачать rw-back-bot.sh"
        print_message "SUCCESS" "Бот скачан"
    fi
    chmod 750 "$BOT_SCRIPT"

    # VERSION
    if [[ "$SELF_IS_SCRIPT" == true && -f "$SELF_DIR/VERSION" ]]; then
        cp -f "$SELF_DIR/VERSION" "$VERSION_FILE"
    elif [[ ! -s "$VERSION_FILE" ]]; then
        fetch_file "$RAW_MAIN/VERSION" "$VERSION_FILE" "" || echo "dev" > "$VERSION_FILE"
    fi

    bash -n "$BOT_SCRIPT" 2>/dev/null || die "Синтаксис rw-back-bot.sh некорректен — установка прервана"
    bash -n "$INSTALL_DIR/install.sh" 2>/dev/null || die "Синтаксис install.sh некорректен"

    chmod 700 "$INSTALL_DIR" "$STATE_DIR" 2>/dev/null || true
    chmod 700 "$BACKUP_DIR" 2>/dev/null || true

    setup_symlink
}

setup_symlink() {
    if [[ -d "$(dirname "$SYMLINK_PATH")" ]]; then
        ln -sfn "$INSTALL_DIR/install.sh" "$SYMLINK_PATH" 2>/dev/null &&
            print_message "SUCCESS" "Команда ${BOLD}rw-back${RESET} доступна" ||
            print_message "WARN" "Не удалось создать ссылку $SYMLINK_PATH"
    fi
}

# ── Первичная привязка главного админа ──────────────────────────────────────
# Установщик показывает 6-значный код, бот принимает его только в личке
# и записывает Telegram ID как главного админа.
generate_setup_code() {
    local raw
    raw=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')
    [[ "$raw" =~ ^[0-9]+$ ]] || raw=$(( (RANDOM * 32768 + RANDOM) ))
    printf '%06d' "$((raw % 1000000))"
}

write_setup_code() {
    local code="$1"
    mkdir -p "$STATE_DIR" || return 1
    umask 077
    printf '%s|%s\n' "$code" "$(date +%s)" > "$STATE_DIR/setup_code" || return 1
    chmod 600 "$STATE_DIR/setup_code" 2>/dev/null
    rm -f "$STATE_DIR/setup_attempts" 2>/dev/null
    return 0
}

bot_username_of() {
    local resp
    [[ -n "$BOT_TOKEN" ]] || return 0
    resp=$(curl -s --max-time 15 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null)
    printf '%s' "$resp" | jq -r '.result.username // empty' 2>/dev/null
}

main_admin_id() {
    grep -m1 '^BOT_ADMIN_IDS=' "$CONFIG_FILE" 2>/dev/null |
        cut -d= -f2- | tr -d '"' | cut -d, -f1 | tr -d '[:space:]'
}

wait_admin_binding() { # таймаут в секундах
    local timeout="${1:-900}" waited=0 id
    while (( waited < timeout )); do
        id="$(main_admin_id)"
        [[ "$id" =~ ^[0-9]+$ ]] && return 0
        sleep 3
        waited=$((waited + 3))
    done
    return 1
}

setup_admin_flow() {
    local existing username code id
    existing="$(main_admin_id)"
    if [[ "$existing" =~ ^[0-9]+$ ]]; then
        print_message "SUCCESS" "Главный админ уже привязан: ${BOLD}${existing}${RESET}"
        return 0
    fi

    username="$(bot_username_of)"
    if [[ -z "$username" ]]; then
        print_message "ERROR" "Telegram не принял токен — привязка невозможна"
        return 1
    fi

    code="$(generate_setup_code)"
    write_setup_code "$code" || { print_message "ERROR" "Не удалось сохранить код"; return 1; }

    echo ""
    echo -e "   ${CYAN}══════════════════════════════════════════${RESET}"
    echo -e "   ${BOLD}🔑 КОД ПРИВЯЗКИ АДМИНА:${RESET}  ${BOLD}${GREEN}${code}${RESET}"
    echo -e "   ${CYAN}══════════════════════════════════════════${RESET}"
    echo ""
    echo -e "   1. Откройте бота:  ${BOLD}https://t.me/${username}${RESET}"
    echo -e "   2. Напишите:       ${BOLD}/start${RESET}"
    echo -e "   3. Отправьте код:  ${BOLD}${GREEN}${code}${RESET}"
    echo ""
    print_message "INFO" "Код действует 1 час. Жду привязку…"

    if wait_admin_binding 900; then
        id="$(main_admin_id)"
        print_message "SUCCESS" "Главный админ привязан: ${BOLD}${id}${RESET}"
        return 0
    fi

    print_message "WARN" "Привязка не произошла. Код остаётся действителен 1 час."
    print_message "INFO" "Новый код в любой момент: ${BOLD}rw-back admin-code${RESET}"
    return 1
}

cmd_admin_code() {
    load_config
    mkdir -p "$STATE_DIR"
    local existing username code
    existing="$(main_admin_id)"
    if [[ "$existing" =~ ^[0-9]+$ ]]; then
        print_message "INFO" "Главный админ уже привязан: ${existing}"
        print_message "INFO" "Добавить других: бот → ⚙️ Настройки → 👥 Админы"
        return 0
    fi
    [[ -n "$BOT_TOKEN" ]] || die "Сначала задайте токен бота: rw-back"
    username="$(bot_username_of)"
    [[ -n "$username" ]] || die "Telegram не принял токен"
    code="$(generate_setup_code)"
    write_setup_code "$code" || die "Не удалось сохранить код"

    echo ""
    print_message "ACTION" "Код привязки: ${BOLD}${GREEN}${code}${RESET} (1 час)"
    echo "  1. Откройте https://t.me/${username}"
    echo "  2. Отправьте /start"
    echo "  3. Отправьте код: ${code}"
    echo ""
    return 0
}

# ── Первичная настройка ─────────────────────────────────────────────────────
wizard() {
    clear 2>/dev/null || true
    echo -e "   ${MAGENTA}${BOLD}💎 RW-BACK · ПЕРВИЧНАЯ НАСТРОЙКА${RESET}"
    echo -e "   ${CYAN}──────────────────────────────────────────${RESET}"
    echo ""

    print_message "ACTION" "1. Telegram"
    echo -e "   Токен бота — у ${CYAN}@BotFather${RESET} (команда /newbot)"
    echo ""
    read -rp "   ${GREEN}──>${RESET} Токен бота: " BOT_TOKEN
    [[ -z "$BOT_TOKEN" ]] && die "Без токена бот работать не сможет"
    local bot_user
    bot_user="$(bot_username_of)"
    [[ -z "$bot_user" ]] && die "Telegram не принял токен — проверьте его в @BotFather"
    print_message "SUCCESS" "Бот: @${bot_user}"
    # главный админ привяжется одноразовым кодом после запуска службы
    BOT_ADMIN_IDS=""
    CHAT_ID=""
    echo ""

    print_message "ACTION" "2. База данных"
    read -rp "   ${GREEN}──>${RESET} Контейнер БД (remnawave-db): " input
    DB_CONTAINER="${input:-remnawave-db}"
    read -rp "   ${GREEN}──>${RESET} Пользователь (postgres): " input
    DB_USER="${input:-postgres}"
    read -rp "   ${GREEN}──>${RESET} Имя базы (postgres): " input
    DB_NAME="${input:-postgres}"
    echo ""

    print_message "ACTION" "3. Панель Remnawave"
    echo "   1. /opt/remnawave"
    echo "   2. /root/remnawave"
    echo "   3. /opt/stacks/remnawave"
    echo "   4. Свой путь"
    local choice
    while true; do
        read -rp "   ${GREEN}──>${RESET} Выберите: " choice
        case "$choice" in
            1) PANEL_DIR="/opt/remnawave"; break ;;
            2) PANEL_DIR="/root/remnawave"; break ;;
            3) PANEL_DIR="/opt/stacks/remnawave"; break ;;
            4)
                read -rp "   Путь: " custom
                if [[ -n "$custom" && "$custom" = /* ]]; then
                    PANEL_DIR="${custom%/}"
                    break
                fi
                print_message "ERROR" "Путь должен быть абсолютным"
                ;;
            *) print_message "ERROR" "Введите 1–4" ;;
        esac
    done
    echo ""

    print_message "ACTION" "4. Хранение архивов"
    read -rp "   ${GREEN}──>${RESET} Сколько файлов хранить (5): " input
    KEEP_FILES="${input:-5}"
    [[ "$KEEP_FILES" =~ ^[0-9]+$ ]] || KEEP_FILES=5

    save_config
    print_message "SUCCESS" "Настройки сохранены"
}

# ── Проверка обновлений ─────────────────────────────────────────────────────
version_compare() { # 0 если $1 < $2
    local a="${1#v}" b="${2#v}"
    [[ "$a" == "$b" ]] && return 1
    local first
    first=$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n 1)
    [[ "$first" == "$a" ]]
}

remote_version() {
    local cache="$STATE_DIR/update_cache" ts ver response
    mkdir -p "$STATE_DIR" 2>/dev/null
    if [[ -f "$cache" ]]; then
        ts=$(cut -d'|' -f1 "$cache" 2>/dev/null)
        ver=$(cut -d'|' -f2 "$cache" 2>/dev/null)
        if [[ "$ts" =~ ^[0-9]+$ ]] && (( $(date +%s) - ts < UPDATE_CACHE_TTL )); then
            printf '%s' "$ver"
            return 0
        fi
    fi

    response=$(curl -s --max-time 10 -H "User-Agent: rw-back" -H "Accept: application/vnd.github+json" \
        "$REPO_API/releases/latest" 2>/dev/null)
    ver=$(printf '%s' "$response" | jq -r '.tag_name // empty' 2>/dev/null)

    if [[ -z "$ver" ]]; then
        ver=$(curl -s --max-time 10 -H "User-Agent: rw-back" "$RAW_MAIN/VERSION" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    fi
    [[ "$ver" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || ver=""
    printf '%s|%s\n' "$(date +%s)" "$ver" > "$cache" 2>/dev/null
    printf '%s' "$ver"
}

update_hint() {
    local current remote
    current="$(local_version)"
    remote="$(remote_version)"
    [[ -z "$remote" ]] && return 0
    if version_compare "$current" "$remote"; then
        printf '%s⬆️ Доступно обновление: %s → %s%s\n' "$YELLOW" "$current" "$remote" "$RESET"
    fi
}

# ── Служба бота ─────────────────────────────────────────────────────────────
bot_service_active() {
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

bot_service_installed() {
    [[ -f "$SERVICE_FILE" ]]
}

install_bot_service() {
    require_root
    [[ -n "$BOT_TOKEN" ]] || die "Сначала задайте токен (Параметры → Telegram)"
    command -v systemctl > /dev/null 2>&1 || die "systemd не найден"

    mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$LOG_DIR"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=rw-back Telegram bot (Remnawave DB import/export)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/bin/bash $BOT_SCRIPT serve
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=rw-back-bot

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SERVICE_FILE"
    systemctl daemon-reload > /dev/null 2>&1 || true
    systemctl enable "$SERVICE_NAME" > /dev/null 2>&1 || true

    if systemctl restart "$SERVICE_NAME" 2>/dev/null; then
        sleep 2
        if bot_service_active; then
            print_message "SUCCESS" "Служба ${SERVICE_NAME} запущена и в автозапуске"
            print_message "INFO" "Логи: journalctl -u ${SERVICE_NAME} -f"
            return 0
        fi
    fi
    print_message "ERROR" "Служба не поднялась. Смотрите: journalctl -u ${SERVICE_NAME} -n 50"
    return 1
}

remove_bot_service() {
    require_root
    systemctl stop "$SERVICE_NAME" > /dev/null 2>&1 || true
    systemctl disable "$SERVICE_NAME" > /dev/null 2>&1 || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload > /dev/null 2>&1 || true
    print_message "SUCCESS" "Служба удалена"
}

cron_remove() {
    command -v crontab > /dev/null 2>&1 || return 0
    (crontab -l 2>/dev/null | grep -v 'rw-back-bot.sh cron') | crontab - 2>/dev/null || true
}

# ── Обновление ──────────────────────────────────────────────────────────────
do_update() { # [--auto]
    local auto="${1:-}"
    require_root
    load_config

    local current remote
    current="$(local_version)"
    remote="$(remote_version)"

    if [[ -z "$remote" ]]; then
        print_message "ERROR" "Не удалось узнать версию с GitHub (нет сети?)"
        return 1
    fi
    if ! version_compare "$current" "$remote"; then
        print_message "SUCCESS" "Уже последняя версия: ${current}"
        return 0
    fi

    print_message "ACTION" "Обновление ${current} → ${remote}"
    if [[ "$auto" != "--auto" ]]; then
        local answer
        read -rp "   Продолжить? (Y/N): " answer
        [[ "${answer,,}" != "y" ]] && { print_message "WARN" "Отменено"; return 0; }
    fi

    local work
    work="$(mktemp -d)" || die "Нет места для загрузки"

    print_message "INFO" "Загружаю новые файлы…"
    if ! curl -fsSL --max-time 60 -H "User-Agent: rw-back" -o "$work/rw-back-bot.sh" "$RAW_MAIN/rw-back-bot.sh"; then
        rm -rf "$work"; die "Не удалось скачать rw-back-bot.sh"
    fi
    if ! curl -fsSL --max-time 60 -H "User-Agent: rw-back" -o "$work/install.sh" "$RAW_MAIN/install.sh"; then
        rm -rf "$work"; die "Не удалось скачать install.sh"
    fi
    curl -fsSL --max-time 60 -H "User-Agent: rw-back" -o "$work/VERSION" "$RAW_MAIN/VERSION" 2>/dev/null || true

    # проверка целостности до замены файлов
    if ! bash -n "$work/rw-back-bot.sh" 2>/dev/null; then
        rm -rf "$work"; die "Новый rw-back-bot.sh не прошёл проверку синтаксиса — обновление отменено"
    fi
    if ! bash -n "$work/install.sh" 2>/dev/null; then
        rm -rf "$work"; die "Новый install.sh не прошёл проверку синтаксиса — обновление отменено"
    fi
    grep -q 'rw-back-bot' "$work/rw-back-bot.sh" || { rm -rf "$work"; die "Файл бота повреждён"; }

    # резервная копия текущих файлов
    local stamp
    stamp="$(date +%Y%m%d_%H%M%S)"
    cp -f "$BOT_SCRIPT" "$INSTALL_DIR/scripts/rw-back-bot.sh.${stamp}.bak" 2>/dev/null || true
    cp -f "$INSTALL_DIR/install.sh" "$INSTALL_DIR/scripts/install.sh.${stamp}.bak" 2>/dev/null || true

    install -m 750 "$work/rw-back-bot.sh" "$BOT_SCRIPT" || die "Не удалось заменить бота"
    install -m 755 "$work/install.sh" "$INSTALL_DIR/install.sh" || die "Не удалось заменить установщик"
    if [[ -s "$work/VERSION" ]]; then
        install -m 644 "$work/VERSION" "$VERSION_FILE"
    fi
    rm -rf "$work"

    setup_symlink

    if bot_service_installed; then
        systemctl daemon-reload > /dev/null 2>&1 || true
        systemctl restart "$SERVICE_NAME" > /dev/null 2>&1 || true
        sleep 2
        if bot_service_active; then
            print_message "SUCCESS" "Обновлено до ${remote}, бот перезапущен"
        else
            print_message "WARN" "Файлы обновлены, но служба не поднялась. Проверьте: journalctl -u ${SERVICE_NAME} -n 50"
        fi
    else
        print_message "SUCCESS" "Обновлено до ${remote}"
    fi
    return 0
}

# ── Деинсталляция ───────────────────────────────────────────────────────────
do_remove() {
    require_root
    echo ""
    print_message "WARN" "Будут удалены:"
    echo "  • служба бота и cron-задача"
    echo "  • команда rw-back"
    echo "  • каталог $INSTALL_DIR (конфиг, состояние, логи)"
    echo ""
    echo -n "Сохранить архивы бэкапов? (Y/n): "
    local keep
    read -r keep

    if [[ "${keep,,}" != "n" ]]; then
        local stash="/root/rw-back-backups-$(date +%Y%m%d_%H%M%S)"
        if [[ -d "$BACKUP_DIR" ]]; then
            mkdir -p "$stash" && cp -a "$BACKUP_DIR"/. "$stash"/ 2>/dev/null || true
            print_message "SUCCESS" "Архивы сохранены: $stash"
        fi
    fi

    remove_bot_service
    cron_remove
    rm -f "$SYMLINK_PATH"
    rm -rf "$INSTALL_DIR"
    print_message "SUCCESS" "rw-back удалён"
    exit 0
}

# ── Выбор файла для восстановления ──────────────────────────────────────────
pick_backup_file() {
    local files=()
    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'rw_db_backup_*.sql.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)

    if [[ ${#files[@]} -eq 0 ]]; then
        print_message "WARN" "В $BACKUP_DIR нет архивов"
        read -rp "Путь к файлу дампа: " manual
        [[ -f "$manual" ]] || { print_message "ERROR" "Файл не найден"; return 1; }
        echo "$manual"
        return 0
    fi

    echo ""
    echo "  Архивы на сервере:"
    local i=1 f
    for f in "${files[@]}"; do
        printf '   %2d) %-46s %8s\n' "$i" "${f##*/}" "$(du -h "$f" | awk '{print $1}')"
        i=$((i + 1))
    done
    echo "    0) Указать путь вручную"
    echo ""

    local choice
    while true; do
        read -rp "Выберите номер: " choice
        [[ "$choice" == "0" ]] && { read -rp "Путь: " manual; [[ -f "$manual" ]] && { echo "$manual"; return 0; }; print_message "ERROR" "Файл не найден"; continue; }
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )); then
            echo "${files[$((choice - 1))]}"
            return 0
        fi
        print_message "ERROR" "Неверный номер"
    done
}

# ── Меню ────────────────────────────────────────────────────────────────────
menu_backup() {
    load_config
    bash "$BOT_SCRIPT" backup
    echo ""
    read -rp "Нажмите Enter…"
}

menu_restore() {
    load_config
    local file
    file="$(pick_backup_file)" || { read -rp "Нажмите Enter…"; return; }
    echo ""
    print_message "WARN" "Текущая база будет перезаписана"
    read -rp "Продолжить? (Y/N): " answer
    [[ "${answer,,}" != "y" ]] && { print_message "INFO" "Отменено"; read -rp "Нажмите Enter…"; return; }

    bash "$BOT_SCRIPT" restore "$file"
    echo ""
    read -rp "Нажмите Enter…"
}

menu_list() {
    load_config
    bash "$BOT_SCRIPT" list
    echo ""
    read -rp "Нажмите Enter…"
}

menu_bot() {
    while true; do
        clear 2>/dev/null || true
        local status="➖ не установлена"
        if bot_service_installed; then
            bot_service_active && status="✅ работает" || status="⛔ остановлена"
        fi

        echo -e "   ${MAGENTA}${BOLD}🤖 TELEGRAM-БОТ${RESET}"
        echo -e "   ${CYAN}──────────────────────────────────────────${RESET}"
        echo ""
        echo -e "   Служба: ${BOLD}${status}${RESET}"
        echo -e "   Бот:     ${BOLD}${BOT_TOKEN:0:10}…${RESET}"
        echo -e "   Админы:  ${BOLD}${BOT_ADMIN_IDS:-не заданы}${RESET}"
        echo ""
        echo -e "   ${BOLD}1.${RESET} ⚙️  Установить / перезапустить службу"
        echo -e "   ${BOLD}2.${RESET} ⛔ Остановить и удалить службу"
        echo -e "   ${BOLD}3.${RESET} 📜 Логи"
        echo -e "   ${BOLD}4.${RESET} ▶️  Запустить в консоли (Ctrl+C — стоп)"
        echo -e "   ${BOLD}5.${RESET} 📨 Тестовое сообщение"
        echo ""
        echo -e "   ${BOLD}0.${RESET} ↩️  Назад"
        echo ""
        read -rp "   ${GREEN}──>${RESET} Действие: " choice
        echo ""

        case "$choice" in
            1) install_bot_service ;;
            2) remove_bot_service ;;
            3)
                journalctl -u "$SERVICE_NAME" -n 40 --no-pager 2>/dev/null || print_message "INFO" "Логов нет"
                ;;
            4) bash "$BOT_SCRIPT" serve ;;
            5)
                if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
                    print_message "ERROR" "Не заданы токен или чат"
                else
                    local resp
                    resp=$(curl -s --max-time 20 "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                        --data-urlencode "chat_id=$CHAT_ID" \
                        --data-urlencode "text=🤖 rw-back: связь установлена" -d "parse_mode=HTML")
                    if printf '%s' "$resp" | jq -e '.ok == true' > /dev/null 2>&1; then
                        print_message "SUCCESS" "Сообщение отправлено"
                    else
                        print_message "ERROR" "Telegram: $(printf '%s' "$resp" | jq -r '.description // "ошибка"')"
                    fi
                fi
                ;;
            0) return ;;
            *) print_message "ERROR" "Неверный ввод" ;;
        esac
        echo ""
        read -rp "Нажмите Enter…"
    done
}

menu_settings() {
    while true; do
        clear 2>/dev/null || true
        echo -e "   ${MAGENTA}${BOLD}⚙️  ПАРАМЕТРЫ${RESET}"
        echo -e "   ${CYAN}──────────────────────────────────────────${RESET}"
        echo ""
        echo -e "   ${BOLD}1.${RESET} 📱 Telegram: токен и чат уведомлений"
        echo -e "   ${BOLD}2.${RESET} 🗄  Контейнер и имя базы"
        echo -e "   ${BOLD}3.${RESET} 📂 Каталог панели"
        echo -e "   ${BOLD}4.${RESET} 👥 Админы бота (обычно через бота)"
        echo -e "   ${BOLD}5.${RESET} 📦 Хранить файлов"
        echo -e "   ${BOLD}6.${RESET} 🔑 Код привязки главного админа"
        echo ""
        echo -e "   ${BOLD}0.${RESET} ↩️  Назад"
        echo ""
        read -rp "   ${GREEN}──>${RESET} Действие: " choice
        echo ""

        case "$choice" in
            1)
                read -rp "   Новый токен (Enter — оставить): " input
                [[ -n "$input" ]] && BOT_TOKEN="$input"
                read -rp "   Новый чат/ID (Enter — оставить): " input
                [[ -n "$input" ]] && CHAT_ID="$input"
                save_config
                print_message "SUCCESS" "Сохранено"
                ;;
            2)
                read -rp "   Контейнер БД (${DB_CONTAINER}): " input
                [[ -n "$input" ]] && DB_CONTAINER="$input"
                read -rp "   Пользователь БД (${DB_USER}): " input
                [[ -n "$input" ]] && DB_USER="$input"
                read -rp "   Имя базы (${DB_NAME}): " input
                [[ -n "$input" ]] && DB_NAME="$input"
                save_config
                print_message "SUCCESS" "Сохранено"
                ;;
            3)
                read -rp "   Каталог панели (${PANEL_DIR}): " input
                if [[ -n "$input" ]]; then
                    [[ "$input" = /* ]] && PANEL_DIR="${input%/}" || print_message "ERROR" "Нужен абсолютный путь"
                fi
                save_config
                print_message "SUCCESS" "Сохранено"
                ;;
            4)
                read -rp "   ID через запятую (${BOT_ADMIN_IDS}): " input
                if [[ "$input" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
                    BOT_ADMIN_IDS="$input"
                    save_config
                    print_message "SUCCESS" "Сохранено"
                else
                    print_message "ERROR" "Только цифры и запятые"
                fi
                ;;
            5)
                read -rp "   Сколько архивов хранить (${KEEP_FILES}): " input
                if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= 200 )); then
                    KEEP_FILES="$input"
                    save_config
                    print_message "SUCCESS" "Сохранено"
                else
                    print_message "ERROR" "Число от 1 до 200"
                fi
                ;;
            6) cmd_admin_code && read -rp "Нажмите Enter…" ;;
            0) return ;;
            *) print_message "ERROR" "Неверный ввод" ;;
        esac
        echo ""
        read -rp "Нажмите Enter…"
    done
}

main_menu() {
    while true; do
        clear 2>/dev/null || true
        local version
        version="$(local_version)"

        echo -e "   ${MAGENTA}${BOLD}💎 RW-BACK${RESET}  ${BOLD}${GRAY}v${version}${RESET}  ${GRAY}(by CyberERROR)${RESET}"
        echo -e "   ${CYAN}──────────────────────────────────────────${RESET}"
        echo ""
        local cron_txt="выключен"
        (( CRON_HOURS > 0 )) && cron_txt="каждые ${CRON_HOURS} ч (в боте)"
        echo -e "   🗄 БД: ${BOLD}${DB_CONTAINER}${RESET} · архивов: ${BOLD}$(find "$BACKUP_DIR" -maxdepth 1 -name 'rw_db_backup_*.sql.gz' 2>/dev/null | wc -l)${RESET}"
        echo -e "   🕒 Автобэкап: ${BOLD}${cron_txt}${RESET}"
        update_hint
        echo ""
        echo -e "   ${BOLD}1.${RESET} 💾 Создать бэкап"
        echo -e "   ${BOLD}2.${RESET} 📥 Восстановить из архива"
        echo -e "   ${BOLD}3.${RESET} 📦 Список архивов"
        echo ""
        echo -e "   ${BOLD}4.${RESET} 🤖 Telegram-бот"
        echo -e "   ${BOLD}5.${RESET} 🛠  Параметры"
        echo -e "   ${BOLD}6.${RESET} 🔄 Проверить обновление"
        echo ""
        echo -e "   ${BOLD}7.${RESET} 🗑  Удалить rw-back"
        echo -e "   ${BOLD}0.${RESET} ❌ Выход"
        echo ""
        echo -e "   ${CYAN}──────────────────────────────────────────${RESET}"
        echo -e "    Команда: ${BOLD}${GREEN}rw-back${RESET}"
        echo ""

        read -rp "   ${GREEN}──>${RESET} Действие: " choice
        echo ""

        case "$choice" in
            1) menu_backup ;;
            2) menu_restore ;;
            3) menu_list ;;
            4) menu_bot ;;
            5) menu_settings ;;
            6) do_update ;;
            7) do_remove ;;
            0) echo "   👋 До встречи!"; exit 0 ;;
            *) print_message "ERROR" "Неверный ввод"; sleep 1 ;;
        esac
    done
}

# ── Точка входа ─────────────────────────────────────────────────────────────
usage() {
    cat <<'TXT'
rw-back — бэкап базы Remnawave + Telegram-бот

  rw-back                открыть меню
  rw-back backup         создать бэкап (отправка админам в Telegram)
  rw-back restore FILE   восстановить БД из файла
  rw-back list           список архивов
  rw-back validate FILE  проверить дамп
  rw-back update         обновить до последней версии
  rw-back admin-code     новый код привязки главного админа
  rw-back bot-install    установить службу бота
  rw-back remove         удалить rw-back
  rw-back version        версия
TXT
}

main() {
    load_config
    local cmd="${1:-}"

    case "$cmd" in
        "")
            require_root
            if [[ ! -x "$BOT_SCRIPT" ]]; then
                clear 2>/dev/null || true
                echo -e "   ${MAGENTA}${BOLD}💎 УСТАНОВКА RW-BACK${RESET}"
                echo -e "   ${CYAN}──────────────────────────────────────────${RESET}"
                echo ""
                install_deps
                install_self
                wizard
                echo ""
                install_bot_service
                setup_admin_flow
                echo ""
                print_message "SUCCESS" "Установка завершена. Открываю меню…"
                sleep 1
            fi
            main_menu
            ;;
        backup|restore|list|validate)
            load_config
            [[ -x "$BOT_SCRIPT" ]] || die "rw-back не установлен. Запустите: $0"
            case "$cmd" in
                backup) exec bash "$BOT_SCRIPT" backup ;;
                list) exec bash "$BOT_SCRIPT" list ;;
                restore) shift; exec bash "$BOT_SCRIPT" restore "$@" ;;
                validate) shift; exec bash "$BOT_SCRIPT" validate "$@" ;;
            esac
            ;;
        install)
            require_root
            install_deps
            install_self
            wizard
            install_bot_service
            setup_admin_flow
            print_message "SUCCESS" "Готово. Запустите: rw-back"
            ;;
        admin-code) cmd_admin_code ;;
        update) do_update ;;
        bot-install) install_bot_service ;;
        bot-remove) remove_bot_service ;;
        remove|uninstall) do_remove ;;
        version|--version|-v) echo "$(local_version)" ;;
        -h|--help|help) usage ;;
        *) usage; exit 1 ;;
    esac
}

main "$@"

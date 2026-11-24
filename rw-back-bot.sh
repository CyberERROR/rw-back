#!/usr/bin/env bash
set -o pipefail

if [[ -t 0 ]]; then
    RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; CYAN=$'\e[36m'
    GRAY=$'\e[37m'; LIGHT_GRAY=$'\e[90m'; RESET=$'\e[0m'
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; GRAY=""; LIGHT_GRAY=""; RESET=""
fi

SELF_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"
SELF_DIR="$(dirname "$SELF_PATH")"
INSTALL_DIR="${RW_BACK_DIR:-/opt/rw-back}"
BACKUP_DIR="$INSTALL_DIR/backup"
STATE_DIR="$INSTALL_DIR/state"
IMPORT_DIR="$STATE_DIR/import_inbox"
SAFETY_DIR="$BACKUP_DIR/pre_restore"
CONFIG_FILE="$INSTALL_DIR/config.env"
VERSION_FILE="$INSTALL_DIR/VERSION"
REPO="CyberERROR/rw-back"
REPO_API="https://api.github.com/repos/$REPO"
RAW_MAIN="https://raw.githubusercontent.com/$REPO/main"

TG_MAX_DOWNLOAD_MB=20
TG_MAX_UPLOAD_MB=50
DUMP_MAX_UNPACK_MB=600
DUMP_MAX_SQL_BYTES=$((DUMP_MAX_UNPACK_MB * 1024 * 1024))
UPDATE_CACHE_TTL=21600
UPDATE_FAIL_CACHE_TTL=60
LOCAL_VERSION="dev"

log() {
    printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

print_message() {
    local type="$1" message="$2" color="$RESET"
    case "$type" in
        SUCCESS) color="$GREEN" ;;
        WARN) color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        ACTION) color="$CYAN" ;;
        INFO) color="$LIGHT_GRAY" ;;
    esac
    printf '%s[%s]%s %s\n' "$color" "$type" "$RESET" "$message"
}

die() {
    print_message "ERROR" "$*"
    exit 1
}

load_config() {
    BOT_TOKEN=""; CHAT_ID=""; BOT_ADMIN_IDS=""
    DB_USER="postgres"; DB_NAME="postgres"; DB_CONTAINER="remnawave-db"
    PANEL_CONTAINER="remnawave"; CACHE_CONTAINER="remnawave-redis"
    CRON_HOURS="0"; KEEP_FILES="5"; PANEL_DIR="/opt/remnawave"

    if [[ -f "$CONFIG_FILE" ]]; then
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

    [[ "$CRON_HOURS" =~ ^[0-9]+$ ]] || CRON_HOURS=0
    [[ "$KEEP_FILES" =~ ^[0-9]+$ ]] || KEEP_FILES=5
    CRON_HOURS=$((10#$CRON_HOURS))
    KEEP_FILES=$((10#$KEEP_FILES))
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

bind_version() {
    LOCAL_VERSION="$(local_version)"
    [[ -z "$LOCAL_VERSION" ]] && LOCAL_VERSION="dev"
}

require_deps() {
    local need=(curl jq gzip)
    local missing=() p
    for p in "${need[@]}"; do
        command -v "$p" > /dev/null 2>&1 || missing+=("$p")
    done
    command -v flock > /dev/null 2>&1 || missing+=("util-linux")
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "не хватает пакетов: ${missing[*]}"
        if command -v apt-get > /dev/null 2>&1; then
            apt-get update -qq > /dev/null 2>&1 || true
            apt-get install -y "${missing[@]}" > /dev/null 2>&1 || true
        fi
    fi
    local fail=0
    for p in "${need[@]}"; do
        command -v "$p" > /dev/null 2>&1 || fail=1
    done
    command -v flock > /dev/null 2>&1 || fail=1
    return $fail
}

have_unzip() {
    command -v unzip > /dev/null 2>&1
}

escape_html() {
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

tg_call() {
    local method="$1"
    shift
    curl -s --max-time 120 "https://api.telegram.org/bot${BOT_TOKEN}/${method}" "$@" 2>/dev/null
}

tg_ok() {
    printf '%s' "$1" | jq -e '.ok == true' > /dev/null 2>&1
}

tg_error_of() {
    printf '%s' "$1" | jq -r '.description // "нет ответа от Telegram"' 2>/dev/null
}

tg_send() {
    local chat_id="$1" text="$2" markup="${3:-}" thread="${4:-}"
    local args=(--data-urlencode "chat_id=$chat_id" --data-urlencode "text=$text" -d "parse_mode=HTML" -d "disable_web_page_preview=true")
    [[ -n "$thread" ]] && args+=(--data-urlencode "message_thread_id=$thread")
    [[ -n "$markup" ]] && args+=(--data-urlencode "reply_markup=$markup")
    local response
    response=$(tg_call sendMessage "${args[@]}")
    if ! tg_ok "$response"; then
        log "sendMessage ${chat_id}: $(tg_error_of "$response")"
    fi
    printf '%s' "$response"
}

tg_edit() {
    local chat_id="$1" message_id="$2" text="$3" markup="${4:-}"
    local args=(--data-urlencode "chat_id=$chat_id" --data-urlencode "message_id=$message_id" --data-urlencode "text=$text" -d "parse_mode=HTML")
    [[ -n "$markup" ]] && args+=(--data-urlencode "reply_markup=$markup")
    tg_call editMessageText "${args[@]}" > /dev/null 2>&1
}

tg_answer() {
    local callback_id="$1" text="${2:-}"
    local args=(--data-urlencode "callback_query_id=$callback_id")
    [[ -n "$text" ]] && args+=(--data-urlencode "text=$text")
    tg_call answerCallbackQuery "${args[@]}" > /dev/null 2>&1
}

tg_doc() {
    local chat_id="$1" file="$2" caption="${3:-}" thread="${4:-}"
    local args=(-F "chat_id=$chat_id" -F "document=@$file" -F "parse_mode=HTML")
    [[ -n "$caption" ]] && args+=(-F "caption=$caption")
    [[ -n "$thread" ]] && args+=(-F "message_thread_id=$thread")
    tg_call sendDocument "${args[@]}"
}

tg_typing() {
    tg_call sendChatAction --data-urlencode "chat_id=$1" -d "action=upload_document" > /dev/null 2>&1
}

msg_id_of() {
    printf '%s' "$1" | jq -r '.result.message_id // empty' 2>/dev/null
}

KB_MAIN='{"inline_keyboard":[[{"text":"💎 Remnawave","callback_data":"m:remna"},{"text":"⚙️ Настройки","callback_data":"m:settings"}]]}'

kb_remna() {
    printf '%s' '{"inline_keyboard":[[{"text":"📤 Экспорт","callback_data":"r:export"},{"text":"📥 Импорт","callback_data":"r:import"}],[{"text":"📦 Бэкапы на сервере","callback_data":"r:list"}],[{"text":"⬅️ Назад","callback_data":"m:main"}]]}'
}

kb_settings() {
    printf '%s' '{"inline_keyboard":[[{"text":"👥 Админы","callback_data":"s:admins"},{"text":"🕒 Расписание","callback_data":"s:schedule"}],[{"text":"📦 Хранить файлов","callback_data":"s:keep"}],[{"text":"⬅️ Назад","callback_data":"m:main"}]]}'
}

kb_back() {
    printf '%s' '{"inline_keyboard":[[{"text":"⬅️ Назад","callback_data":"m:main"}]]}'
}

kb_import_confirm() {
    printf '%s' '{"inline_keyboard":[[{"text":"✅ Восстановить","callback_data":"i:yes"},{"text":"❌ Отмена","callback_data":"i:no"}]]}'
}

normalize_ids() {
    printf '%s' "$1" | tr -d ' ' | sed -e 's/,,\+/,/g' -e 's/^,//' -e 's/,$//'
}

is_admin() {
    local uid="$1"
    [[ -z "$uid" ]] && return 1
    local list
    list=",$(normalize_ids "$BOT_ADMIN_IDS"),"
    [[ "$list" == *",${uid},"* ]]
}

admin_count() {
    local ids
    ids="$(normalize_ids "$BOT_ADMIN_IDS")"
    if [[ -z "$ids" ]]; then
        echo 0
    else
        awk -F',' '{print NF}' <<< "$ids"
    fi
}

admin_list_text() {
    local ids id out="" i=1
    local -a arr=()
    ids="$(normalize_ids "$BOT_ADMIN_IDS")"
    if [[ -z "$ids" ]]; then
        echo "—"
        return
    fi
    IFS=',' read -ra arr <<< "$ids"
    for id in "${arr[@]}"; do
        out+="${i}. <code>${id}</code>"$'\n'
        i=$((i + 1))
    done
    printf '%s' "$out"
}

SETUP_CODE_TTL=1800
SETUP_MAX_ATTEMPTS=10

setup_code_current() {
    local file="$STATE_DIR/setup_code" code ts now
    [[ -f "$file" ]] || return 0
    IFS='|' read -r code ts < "$file" 2>/dev/null || return 0
    [[ "$code" =~ ^[0-9]{6}$ ]] || return 0
    [[ "$ts" =~ ^[0-9]+$ ]] || return 0
    now=$(date +%s)
    (( now - ts > SETUP_CODE_TTL )) && return 0
    printf '%s' "$code"
}

setup_code_clear() {
    rm -f "$STATE_DIR/setup_code" "$STATE_DIR/setup_attempts" 2>/dev/null
    return 0
}

setup_attempts_add() {
    local file="$STATE_DIR/setup_attempts" n=0
    [[ -f "$file" ]] && n=$(head -n 1 "$file" 2>/dev/null)
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    n=$((n + 1))
    mkdir -p "$STATE_DIR" 2>/dev/null
    echo "$n" > "$file" 2>/dev/null
    printf '%s' "$n"
}

bind_main_admin() {
    local uid="$1" old_ids="$BOT_ADMIN_IDS" old_chat="$CHAT_ID"
    BOT_ADMIN_IDS="$uid"
    if [[ -z "$CHAT_ID" || ! "$CHAT_ID" =~ ^[0-9]+$ ]]; then
        CHAT_ID="$uid"
    fi
    if ! save_config; then
        BOT_ADMIN_IDS="$old_ids"
        CHAT_ID="$old_chat"
        return 1
    fi
    setup_code_clear
}

handle_binding() {
    local kind="$1" chat_id="$2" thread="$3" uid="$4" text="$5" cb_id="$6"

    [[ "$kind" == "callback" ]] && tg_answer "$cb_id" "введите код из установщика"

    if [[ "$chat_id" != "$uid" ]]; then
        tg_send "$uid" "🔒 <b>Привязка админа</b>
➖➖➖➖➖
Только в личке с ботом. Отправьте /start." "" > /dev/null 2>&1 || true
        return 0
    fi

    local code
    code="$(setup_code_current)"
    if [[ -z "$code" ]]; then
        tg_send "$chat_id" "🔒 <b>Бот ещё не настроен</b>
➖➖➖➖➖
Запустите на сервере <code>rw-back</code>
и отправьте код, который он покажет." "" "$thread" > /dev/null
        return 0
    fi

    local input
    input="$(printf '%s' "$text" | tr -dc '0-9')"

    if [[ -z "$input" ]]; then
        tg_send "$chat_id" "🔑 <b>Введите код из установщика</b>
➖➖➖➖➖
6 цифр · осталось попыток: <b>${SETUP_MAX_ATTEMPTS}</b>" "" "$thread" > /dev/null
        return 0
    fi

    if [[ "$input" == "$code" ]]; then
        if ! bind_main_admin "$uid"; then
            tg_send "$chat_id" "❌ Не удалось сохранить админа. Проверьте права на <code>${CONFIG_FILE}</code> и повторите код." "" "$thread" > /dev/null
            return 0
        fi
        tg_send "$chat_id" "✅ <b>Вы главный админ</b>
➖➖➖➖➖
ID: <code>${uid}</code>
Добавить других: ⚙️ Настройки → 👥 Админы

$(start_text)" "$KB_MAIN" "$thread" > /dev/null
        notify_chat_text "✅ <b>rw-back</b>: главный админ привязан (<code>${uid}</code>)"
        log "привязан главный админ: $uid"
        return 0
    fi

    local attempts left
    attempts="$(setup_attempts_add)"
    left=$((SETUP_MAX_ATTEMPTS - attempts))
    if (( left <= 0 )); then
        setup_code_clear
        tg_send "$chat_id" "⛔ <b>Слишком много попыток</b>
➖➖➖➖➖
Код сброшен. Новый: <code>rw-back admin-code</code> на сервере." "" "$thread" > /dev/null
        log "привязка: превышено число попыток (uid=$uid)"
        return 0
    fi

    tg_send "$chat_id" "🔑 <b>Введите код из установщика</b>
➖➖➖➖➖
6 цифр · осталось попыток: <b>${left}</b>" "" "$thread" > /dev/null
    return 0
}

version_compare() {
    local a="${1#v}" b="${2#v}"
    [[ "$a" == "$b" ]] && return 1
    [[ "$b" =~ ^[0-9]+([.][0-9]+)*$ ]] || return 1
    [[ "$a" =~ ^[0-9]+([.][0-9]+)*$ ]] || return 0
    local first
    first=$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n 1)
    [[ "$first" == "$a" ]]
}

update_check() {
    local cache="$STATE_DIR/update_cache"
    mkdir -p "$STATE_DIR" 2>/dev/null
    if [[ -f "$cache" ]]; then
        local ts ver
        ts=$(cut -d'|' -f1 "$cache" 2>/dev/null)
        ver=$(cut -d'|' -f2 "$cache" 2>/dev/null)
        if [[ "$ts" =~ ^[0-9]+$ ]]; then
            if [[ -n "$ver" ]] && (( $(date +%s) - ts < UPDATE_CACHE_TTL )); then
                printf '%s' "$ver"
                return 0
            fi
            if [[ -z "$ver" ]] && (( $(date +%s) - ts < UPDATE_FAIL_CACHE_TTL )); then
                return 0
            fi
        fi
    fi

    local remote="" response
    response=$(curl -s --max-time 10 -H "User-Agent: rw-back-bot" -H "Accept: application/vnd.github+json" \
        "$REPO_API/releases/latest" 2>/dev/null)
    if tg_ok_like "$response"; then
        remote=$(printf '%s' "$response" | jq -r '.tag_name // empty' 2>/dev/null)
    fi
    if [[ -z "$remote" ]]; then
        remote=$(curl -s --max-time 10 -H "User-Agent: rw-back-bot" "$RAW_MAIN/VERSION" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    fi
    [[ "$remote" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || remote=""
    printf '%s|%s\n' "$(date +%s)" "$remote" > "$cache" 2>/dev/null
    printf '%s' "$remote"
}

tg_ok_like() {
    printf '%s' "$1" | jq -e '.tag_name != null' > /dev/null 2>&1
}

update_line() {
    local remote
    remote="$(update_check)"
    [[ -z "$remote" ]] && return 0
    if version_compare "$LOCAL_VERSION" "$remote"; then
        printf '\n\n⬆️ <b>Доступно обновление %s</b>\n<code>rw-back update</code>' "$(escape_html "$remote")"
    fi
}

db_running() {
    docker container inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null | grep -q true
}

panel_running() {
    docker container inspect -f '{{.State.Running}}' "$PANEL_CONTAINER" 2>/dev/null | grep -q true
}

panel_exists() {
    docker container inspect "$PANEL_CONTAINER" > /dev/null 2>&1
}

panel_stop() {
    panel_running || return 0
    docker stop "$PANEL_CONTAINER" > /dev/null 2>&1
}

panel_start() {
    panel_exists || return 0
    panel_running && return 0
    docker start "$PANEL_CONTAINER" > /dev/null 2>&1
}

cache_reset() {
    docker container inspect "$CACHE_CONTAINER" > /dev/null 2>&1 || return 0
    docker restart "$CACHE_CONTAINER" > /dev/null 2>&1 || true
}

panel_image() {
    local image
    image=$(docker inspect --format '{{index .Config.Image}}' "$PANEL_CONTAINER" 2>/dev/null || true)
    echo "${image:-—}"
}

db_size_text() {
    db_running || { echo "—"; return 0; }
    local size
    size=$(docker exec "$DB_CONTAINER" psql -tAq -U "$DB_USER" -d "$DB_NAME" \
        -c "select pg_size_pretty(pg_database_size(current_database()))" 2>/dev/null | tr -d '[:space:]')
    echo "${size:-—}"
}

wait_panel_healthy() {
    local timeout="${1:-180}" waited=0 status
    panel_exists || return 0
    while (( waited < timeout )); do
        status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$PANEL_CONTAINER" 2>/dev/null)
        case "$status" in
            healthy) return 0 ;;
            unhealthy) return 1 ;;
            none)
                if docker exec "$PANEL_CONTAINER" curl -fsS -m 3 "http://127.0.0.1:3001/health" > /dev/null 2>&1; then
                    return 0
                fi
                ;;
        esac
        sleep 3
        waited=$((waited + 3))
    done
    return 1
}

dump_to_file() {
    local out="$1" err="${2:-/dev/null}"
    db_running || return 1
    mkdir -p "$(dirname "$out")" || return 1
    if ! ( set -o pipefail; docker exec "$DB_CONTAINER" pg_dumpall -c -U "$DB_USER" 2> "$err" | gzip -9 > "$out" ); then
        rm -f "$out"
        return 1
    fi
    [[ -s "$out" ]] || { rm -f "$out"; return 1; }
    gzip -t "$out" > /dev/null 2>&1 || { rm -f "$out"; return 1; }
    return 0
}

free_space_bytes() {
    df -Pk "$INSTALL_DIR" 2>/dev/null | awk 'NR==2{print $4 * 1024}'
}

VD_SQL=""; VD_KIND=""; VD_TABLES=""; VD_COPY=0; VD_INSERTS=0
VD_TYPE=""; VD_PGVERSION=""; VD_LIST=""; VD_REASON=""; VD_WORK=""; VD_SQL_RESULT=""

vd_fail() {
    VD_REASON="$1"
    return 1
}

vd_scan_sql() {
    local file="$1"
    awk '
        BEGIN { incopy = 0 }
        /^COPY .* FROM stdin;[[:space:]]*$/ { incopy = 1; next }
        incopy == 1 && /^\\\.[[:space:]]*$/ { incopy = 0; next }
        incopy == 1 { next }
        {
            line = $0
            low = tolower(line)

            if (line ~ /^[[:space:]]*\\/) {
                cmd = line
                sub(/^[[:space:]]*/, "", cmd)
                match(cmd, /^\\[A-Za-z!?.]+/)
                cmd = substr(cmd, RSTART, RLENGTH)
                if (cmd ~ /^\\connect$/) {
                    db = line
                    sub(/.*\\connect[[:space:]]+/, "", db)
                    gsub(/["'\'';[:space:]]/, "", db)
                    if (db != "postgres" && db != ENVIRON["VD_EXPECT_DB"]) {
                        printf "BLOCK:строка %d: подключение к чужой БД \\connect %s\n", NR, db
                    }
                    next
                }
                if (cmd == "\\restrict" || cmd == "\\unrestrict" || cmd == "\\." || cmd == "\\N") next
                printf "BLOCK:строка %d: запрещённая мета-команда %s\n", NR, cmd
                next
            }

            if (low ~ /^[[:space:]]*copy[[:space:]]/) {
                if (low ~ /program/) {
                    printf "BLOCK:строка %d: COPY с PROGRAM\n", NR
                } else if (low ~ /(to|from)[[:space:]]+'"'"'/) {
                    printf "BLOCK:строка %d: COPY в файл/из файла\n", NR
                }
                next
            }

            if (low ~ /alter[[:space:]]+system/) { printf "BLOCK:строка %d: ALTER SYSTEM\n", NR; next }
            if (low ~ /create[[:space:]]+extension/) { printf "BLOCK:строка %d: CREATE EXTENSION\n", NR; next }
            if (low ~ /pg_read_file|pg_write_file|pg_ls_dir|lo_import|lo_export|dblink/) {
                printf "BLOCK:строка %d: доступ к файлам/внешним БД\n", NR; next
            }
            if (low ~ /create[[:space:]]+role/ && low ~ /superuser/) {
                printf "BLOCK:строка %d: создание SUPERUSER\n", NR; next
            }
        }
    ' "$file" 2>/dev/null
}

vd_collect_meta() {
    VD_TABLES=""
    VD_TABLES=$(grep -a -o -i -E 'CREATE TABLE (IF NOT EXISTS )?(public\.)?"?[a-zA-Z0-9_]+"?' "$1" 2>/dev/null |
        sed -E 's/.*CREATE TABLE (IF NOT EXISTS )?(public\.)?"?//I; s/"$//' |
        tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' ' ')
    VD_COPY=$(grep -a -c -E '^COPY .* FROM stdin;' "$1" 2>/dev/null | head -n 1 || true)
    VD_INSERTS=$(grep -a -c -i -E '^INSERT INTO ' "$1" 2>/dev/null | head -n 1 || true)
    [[ "$VD_COPY" =~ ^[0-9]+$ ]] || VD_COPY=0
    [[ "$VD_INSERTS" =~ ^[0-9]+$ ]] || VD_INSERTS=0
    VD_PGVERSION=$(grep -a -m1 -E '^-- Dumped from database version' "$1" 2>/dev/null | sed -E 's/.*version ([0-9.]+).*/\1/')
}

vd_tables_ok() {
    local required="users" found=0 total=0 t
    [[ "$VD_TABLES" == *" $required "* || "$VD_TABLES" == "$required "* ]] || return 1
    for t in users nodes hosts config_profiles api_tokens admin user_traffic subscription_settings internal_squads external_squads node_plugin; do
        if [[ "$VD_TABLES" == *" $t "* || "$VD_TABLES" == "$t "* ]]; then
            found=$((found + 1))
        fi
    done
    total=$found
    (( total >= 3 ))
}

vd_extract_sql() {
    local file="$1" work="$2" magic kind
    VD_SQL_RESULT=""

    magic=$(head -c 4 "$file" 2>/dev/null | od -An -tx1 | tr -d ' \n')
    case "$magic" in
        1f8b*) kind="gzip" ;;
        504b*) kind="zip" ;;
        *) kind="plain" ;;
    esac

    case "$kind" in
        gzip)
            VD_KIND="gzip"
            local out="$work/dump.sql"
            if ! ( set -o pipefail; gzip -dc "$file" 2>/dev/null | head -c $((DUMP_MAX_SQL_BYTES + 1)) > "$out" ); then
                true
            fi
            local size
            size=$(stat -c %s "$out" 2>/dev/null || echo 0)
            if (( size > DUMP_MAX_SQL_BYTES )); then
                rm -f "$out"
                vd_fail "архив распаковывается в слишком большой файл (защита от «бомбы»)"
                return 1
            fi
            if ! gzip -t "$file" > /dev/null 2>&1; then
                rm -f "$out"
                vd_fail "gzip-архив повреждён или неполный"
                return 1
            fi
            (( size > 0 )) || { rm -f "$out"; vd_fail "gzip-архив пустой или повреждён"; return 1; }
            VD_SQL_RESULT="$out"
            ;;
        zip)
            VD_KIND="zip"
            if ! have_unzip; then
                if command -v apt-get > /dev/null 2>&1; then
                    apt-get install -y unzip > /dev/null 2>&1 || true
                fi
            fi
            if ! have_unzip; then
                vd_fail "на сервере нет unzip — пришлите .sql.gz"
                return 1
            fi

            local listing entries count ext
            listing=$(unzip -Z1 "$file" 2>/dev/null) || { vd_fail "архив не читается (повреждён zip)"; return 1; }
            entries=$(printf '%s\n' "$listing" | sed '/^$/d')
            count=$(printf '%s\n' "$entries" | wc -l | tr -d ' ')

            if printf '%s\n' "$entries" | grep -q -E '(^|/)\.\.(/|$)|^/'; then
                vd_fail "небезопасные пути внутри zip (обход каталога)"
                return 1
            fi
            if (( count < 1 )); then
                vd_fail "zip-архив пуст"
                return 1
            fi
            if (( count > 1 )); then
                VD_LIST=$(printf '%s' "$entries" | head -n 6 | tr '\n' ' ')
                vd_fail "в zip должно быть ровно один файл дампа, найдено ${count}: ${VD_LIST}"
                return 1
            fi
            ext="${entries##*.}"
            ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
            if [[ "$ext" != "sql" && "$ext" != "gz" ]]; then
                vd_fail "внутри zip не дамп, а «.${ext}» — нужен .sql или .sql.gz"
                return 1
            fi

            local out="$work/dump_from_zip"
            if ! ( set -o pipefail; unzip -p "$file" "$entries" 2>/dev/null | head -c $((DUMP_MAX_SQL_BYTES + 1)) > "$out" ); then
                true
            fi
            local size
            size=$(stat -c %s "$out" 2>/dev/null || echo 0)
            if (( size > DUMP_MAX_SQL_BYTES )); then
                rm -f "$out"
                vd_fail "содержимое zip больше допустимого (защита от «бомбы»)"
                return 1
            fi
            if ! unzip -t "$file" > /dev/null 2>&1; then
                rm -f "$out"
                vd_fail "zip-архив повреждён или неполный"
                return 1
            fi
            (( size > 0 )) || { rm -f "$out"; vd_fail "внутри zip пустой файл"; return 1; }

            if [[ "$ext" == "gz" ]]; then
                local inner="$work/dump.sql"
                if ! ( set -o pipefail; gzip -dc "$out" 2>/dev/null | head -c $((DUMP_MAX_SQL_BYTES + 1)) > "$inner" ); then
                    true
                fi
                size=$(stat -c %s "$inner" 2>/dev/null || echo 0)
                if (( size > DUMP_MAX_SQL_BYTES )); then
                    rm -f "$inner" "$out"
                    vd_fail "вложенный gzip распаковывается в слишком большой файл"
                    return 1
                fi
                if ! gzip -t "$out" > /dev/null 2>&1; then
                    rm -f "$inner" "$out"
                    vd_fail "вложенный gzip повреждён или неполный"
                    return 1
                fi
                rm -f "$out"
                (( size > 0 )) || { rm -f "$inner"; vd_fail "вложенный gzip пустой"; return 1; }
                VD_SQL_RESULT="$inner"
            else
                VD_SQL_RESULT="$out"
            fi
            ;;
        *)
            VD_KIND="plain"
            local size
            size=$(stat -c %s "$file" 2>/dev/null || echo 0)
            if (( size > DUMP_MAX_SQL_BYTES )); then
                vd_fail "файл слишком большой для проверки"
                return 1
            fi
            if ! LC_ALL=C grep -aq -m1 -E '^-- (PostgreSQL database dump|Dumped from database version)|^SET |^CREATE TABLE|^COPY ' "$file" 2>/dev/null; then
                vd_fail "это не SQL-дамп PostgreSQL"
                return 1
            fi
            VD_SQL_RESULT="$file"
            ;;
    esac
}

validate_dump() {
    local file="$1"
    VD_SQL=""; VD_REASON=""; VD_KIND=""; VD_TYPE=""; VD_LIST=""; VD_TABLES=""; VD_COPY=0; VD_INSERTS=0; VD_WORK=""

    [[ -f "$file" ]] || { vd_fail "файл не найден"; return 1; }
    [[ -s "$file" ]] || { vd_fail "файл пустой"; return 1; }

    local work
    work="$(mktemp -d "$STATE_DIR/vd.XXXXXX" 2>/dev/null)" || { vd_fail "нет места для временных файлов"; return 1; }
    VD_WORK="$work"

    local sql
    if ! vd_extract_sql "$file" "$work"; then
        cleanup_vd
        return 1
    fi
    sql="$VD_SQL_RESULT"
    [[ -s "$sql" ]] || { vd_fail "не удалось получить SQL"; return 1; }

    VD_SQL="$sql"
    VD_TYPE="$VD_KIND"

    if ! grep -aq -m1 -E '^-- PostgreSQL database dump|^-- Dumped from database version' "$sql" 2>/dev/null; then
        rm -rf "$work"; vd_fail "нет заголовка pg_dump — файл создан не pg_dump/pg_dumpall"
        return 1
    fi

    local blocks
    VD_EXPECT_DB="$DB_NAME"
    export VD_EXPECT_DB
    blocks=$(vd_scan_sql "$sql")
    if [[ -n "$blocks" ]]; then
        VD_LIST=$(printf '%s' "$blocks" | head -n 3 | tr '\n' '; ')
        rm -rf "$work"
        vd_fail "в дампе опасные конструкции: ${VD_LIST}"
        return 1
    fi

    vd_collect_meta "$sql"
    if ! vd_tables_ok; then
        rm -rf "$work"
        vd_fail "в дампе не найдена база Remnawave (нет таблиц users/nodes/hosts)"
        return 1
    fi
    if (( VD_COPY == 0 && VD_INSERTS == 0 )); then
        rm -rf "$work"
        vd_fail "в дампе нет данных (ни COPY, ни INSERT)"
        return 1
    fi

    return 0
}

cleanup_vd() {
    if [[ -n "$VD_WORK" && -d "$VD_WORK" ]]; then
        rm -rf "$VD_WORK"
    fi
    VD_WORK=""
    VD_SQL=""
}

restore_sql_file() {
    local sql="$1" target_db="${2:-}" safety="${3:-}" log_file rollback_log
    log_file="$STATE_DIR/restore_$(date +%s)_$$.log"
    rollback_log="$STATE_DIR/rollback_$(date +%s)_$$.log"
    RESTORE_ROLLBACK_LOG=""

    [[ -n "$target_db" ]] || target_db="$DB_NAME"
    if head -n 400 "$sql" 2>/dev/null | grep -q -i "CREATE DATABASE"; then
        target_db="postgres"
    fi

    if ! panel_stop; then
        log "не удалось остановить панель — восстановление не начато"
        RESTORE_ROLLED_BACK=0
        RESTORE_ERRORS=0
        RESTORE_LOG="$log_file"
        return 1
    fi
    local rc=0
    docker exec -i "$DB_CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$target_db" \
        > /dev/null 2> "$log_file" < "$sql" || rc=$?
    cache_reset
    panel_start || log "не удалось запустить панель после восстановления"

    local errors
    errors=$(grep -c -E '(^|:)[[:space:]]*(ERROR|FATAL):' "$log_file" 2>/dev/null | head -n 1 || true)
    [[ "$errors" =~ ^[0-9]+$ ]] || errors=0

    if (( rc != 0 || errors > 0 )) || ! wait_panel_healthy 180; then
        log "восстановление не прошло (psql=$rc, ошибок=$errors)"
        RESTORE_ROLLED_BACK=0
        if [[ -n "$safety" && -f "$safety" ]]; then
            log "откат к страховочному дампу"
            local rollback_rc=0 rollback_errors=0
            panel_stop || rollback_rc=1
            if (( rollback_rc == 0 )); then
                if [[ "$safety" == *.gz ]]; then
                    ( set -o pipefail; gzip -dc "$safety" 2>> "$rollback_log" | docker exec -i "$DB_CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$target_db" \
                        > /dev/null 2>> "$rollback_log" ) || rollback_rc=$?
                else
                    docker exec -i "$DB_CONTAINER" psql -q -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$target_db" \
                        > /dev/null 2>> "$rollback_log" < "$safety" || rollback_rc=$?
                fi
            fi
            rollback_errors=$(grep -c -E '(^|:)[[:space:]]*(ERROR|FATAL):' "$rollback_log" 2>/dev/null | head -n 1 || true)
            [[ "$rollback_errors" =~ ^[0-9]+$ ]] || rollback_errors=0
            (( rollback_errors == 0 )) || rollback_rc=1
            cache_reset
            panel_start || rollback_rc=1
            RESTORE_ROLLBACK_LOG="$rollback_log"
            if (( rollback_rc == 0 )) && wait_panel_healthy 180; then
                RESTORE_ROLLED_BACK=1
            else
                log "откат завершился ошибкой (код=$rollback_rc, SQL-ошибок=$rollback_errors): $rollback_log"
            fi
        fi
        RESTORE_ERRORS="$errors"
        RESTORE_LOG="$log_file"
        return 1
    fi

    RESTORE_ROLLED_BACK=0
    RESTORE_ERRORS="$errors"
    RESTORE_LOG="$log_file"
    return 0
}

apply_retention() {
    local keep="${1:-$KEEP_FILES}"
    [[ "$keep" =~ ^[0-9]+$ ]] || keep=5
    (( keep < 1 )) && keep=1

    local files=()
    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'rw_db_backup_*.sql.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)

    local i=0 f
    for f in "${files[@]}"; do
        i=$((i + 1))
        if (( i > keep )); then
            rm -f "$f" 2>/dev/null || true
        fi
    done

    local safes=()
    mapfile -t safes < <(find "$SAFETY_DIR" -maxdepth 1 -type f -name 'pre_restore_*.sql.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)
    i=0
    for f in "${safes[@]}"; do
        i=$((i + 1))
        if (( i > 3 )); then
            rm -f "$f" 2>/dev/null || true
        fi
    done

    find "$IMPORT_DIR" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true
}

list_backups() {
    find "$BACKUP_DIR" -maxdepth 1 -type f -name 'rw_db_backup_*.sql.gz' -printf '%T@ %p\n' 2>/dev/null |
        sort -nr | cut -d' ' -f2-
}

human_size() {
    du -h "$1" 2>/dev/null | awk '{print $1}'
}

bytes_of() {
    stat -c %s "$1" 2>/dev/null || echo 0
}

notify_admins_text() {
    local text="$1" uid
    local ids
    local -a arr=()
    ids="$(normalize_ids "$BOT_ADMIN_IDS")"
    [[ -z "$ids" ]] && return 0
    IFS=',' read -ra arr <<< "$ids"
    for uid in "${arr[@]}"; do
        tg_send "$uid" "$text" > /dev/null 2>&1 || true
    done
}

notify_chat_text() {
    [[ -z "$CHAT_ID" ]] && return 0
    tg_send "$CHAT_ID" "$1" > /dev/null 2>&1 || true
}

start_text() {
    local upd
    upd="$(update_line)"
    local cron_txt="выключено"
    (( CRON_HOURS > 0 )) && cron_txt="каждые ${CRON_HOURS} ч"
    local db_state="нет"
    db_running && db_state="запущена"

    printf '%s' "🗄 <b>rw-back</b> · <code>v$(escape_html "$LOCAL_VERSION")</code>
➖➖➖➖➖
💾 Бэкап базы Remnawave
🗓 Расписание: <b>${cron_txt}</b>
📦 Хранить: <b>${KEEP_FILES}</b> шт.
🔌 БД: <b>${db_state}</b>${upd}"
}

remna_text() {
    local db_state="❌ остановлена"
    db_running && db_state="✅ работает"
    printf '%s' "💎 <b>Remnawave</b>
➖➖➖➖➖
🗄 БД <code>$(escape_html "$DB_NAME")</code>: ${db_state}
💾 Размер: <b>$(db_size_text)</b>
🖥 Панель: <code>$(escape_html "$(panel_image)")</code>

Экспорт — дамп файлом в чат.
Импорт — пришлёте дамп, восстановлю."
}

settings_text() {
    local cron_txt="выключено"
    (( CRON_HOURS > 0 )) && cron_txt="каждые ${CRON_HOURS} ч"
    printf '%s' "⚙️ <b>Настройки</b>
➖➖➖➖➖
👥 Админов: <b>$(admin_count)</b>
🕒 Расписание: <b>${cron_txt}</b>
📦 Хранить файлов: <b>${KEEP_FILES}</b>"
}

admins_text() {
    printf '%s' "👥 <b>Админы бота</b>
➖➖➖➖➖
$(admin_list_text)

Только они могут делать импорт и экспорт."
}

kb_admins() {
    printf '%s' '{"inline_keyboard":[[{"text":"➕ Добавить","callback_data":"a:add"},{"text":"🗑 Удалить","callback_data":"a:del"}],[{"text":"⬅️ Назад","callback_data":"s:menu"}]]}'
}

kb_schedule() {
    local off_text="⏰ Выключить"
    printf '%s' '{"inline_keyboard":[[{"text":"3 ч","callback_data":"h:3"},{"text":"6 ч","callback_data":"h:6"},{"text":"12 ч","callback_data":"h:12"}],[{"text":"24 ч","callback_data":"h:24"},{"text":"✏️ Своё","callback_data":"h:custom"}],[{"text":"'"$off_text"'","callback_data":"h:0"}],[{"text":"⬅️ Назад","callback_data":"s:menu"}]]}'
}

kb_keep() {
    printf '%s' '{"inline_keyboard":[[{"text":"2","callback_data":"k:2"},{"text":"5","callback_data":"k:5"},{"text":"10","callback_data":"k:10"}],[{"text":"✏️ Своё значение","callback_data":"k:custom"}],[{"text":"⬅️ Назад","callback_data":"s:menu"}]]}'
}

schedule_text() {
    local cron_txt="выключено"
    (( CRON_HOURS > 0 )) && cron_txt="каждые ${CRON_HOURS} ч"
    printf '%s' "🕒 <b>Расписание автобэкапа</b>
➖➖➖➖➖
Сейчас: <b>${cron_txt}</b>

Выберите интервал — дамп будет приходить в личку админам." 
}

keep_text() {
    printf '%s' "📦 <b>Сколько архивов хранить</b>
➖➖➖➖➖
Сейчас: <b>${KEEP_FILES}</b> шт.

Старые удаляются автоматически после каждого бэкапа." 
}

limits_instruction() {
    local kind="$1" size="${2:-}" path="${3:-}"
    local head target
    if [[ "$kind" == "upload" ]]; then
        head="⚠️ <b>Файл больше лимита Telegram</b>"
    else
        head="⚠️ <b>Слишком большой файл для бота</b>"
    fi
    target="${path:-$BACKUP_DIR/backup.sql.gz}"

    printf '%s%s' "$head" "
➖➖➖➖➖
📏 Размер: <b>${size:-неизвестен}</b>
📉 Лимиты Bot API: скачивание — ${TG_MAX_DOWNLOAD_MB} МБ, отправка — ${TG_MAX_UPLOAD_MB} МБ

<b>Что делать — по шагам:</b>

1️⃣ Подключитесь к серверу:
<code>ssh root@ВАШ_IP</code>

2️⃣ Проверьте, что панель работает:
<code>docker ps | grep remnawave</code>

3️⃣ Создайте папку и положите туда файл:
<code>mkdir -p $BACKUP_DIR</code>
<code>scp backup.sql.gz root@ВАШ_IP:$target</code>

4️⃣ Проверьте файл перед восстановлением:
<code>rw-back validate $target</code>

5️⃣ Запустите восстановление:
<code>rw-back restore $target</code>

6️⃣ Или через меню:
<code>rw-back</code> → «Восстановить из архива»

💡 Страховочный дамп текущей БД создаётся автоматически.
🛡 Панель на время импорта останавливается и поднимается обратно."
}

flow_export() {
    local chat_id="$1" thread="$2" uid="$3"
    local notify_to="$chat_id"
    local note=""
    if [[ "$chat_id" == -* ]]; then
        notify_to="$uid"
        note=$'\n\n📬 Файл отправлен вам в личку — в этом чате не публикую.'
    fi

    local status_json status_id
    status_json=$(tg_send "$notify_to" "⏳ <b>Собираю дамп базы…</b>" "" "$thread")
    status_id="$(msg_id_of "$status_json")"
    tg_typing "$notify_to"

    mkdir -p "$BACKUP_DIR" || {
        tg_send "$notify_to" "❌ Нет доступа к папке бэкапов." "$(kb_remna)" "$thread" > /dev/null
        return 0
    }

    local free need
    free=$(free_space_bytes)
    free=${free:-0}
    if (( free > 0 && free < 200 * 1024 * 1024 )); then
        tg_send "$notify_to" "❌ Мало места на диске (< 200 МБ). Освободите место и повторите." "$(kb_remna)" "$thread" > /dev/null
        return 0
    fi

    local ts file err
    ts="$(date +%Y-%m-%d_%H_%M_%S)"
    file="$BACKUP_DIR/rw_db_backup_${ts}.sql.gz"
    err="$STATE_DIR/dump_${ts}.err"

    if ! dump_to_file "$file" "$err"; then
        local reason="pg_dumpall вернул ошибку"
        [[ -s "$err" ]] && reason=$(tail -n 3 "$err" | tr '\n' ' ')
        rm -f "$err"
        if [[ -n "$status_id" ]]; then
            tg_edit "$notify_to" "$status_id" "❌ <b>Дамп не создан</b>
➖➖➖➖➖
$(escape_html "$reason")" "$(kb_remna)"
        else
            tg_send "$notify_to" "❌ <b>Дамп не создан</b>
➖➖➖➖➖
$(escape_html "$reason")" "$(kb_remna)" "$thread" > /dev/null
        fi
        return 0
    fi
    rm -f "$err"

    apply_retention "$KEEP_FILES"

    local size_bytes size_h upd caption
    size_bytes=$(bytes_of "$file")
    size_h=$(human_size "$file")
    upd="$(update_line)"

    caption="💎 <b>Бэкап базы Remnawave</b>
➖➖➖➖➖
🗄 БД: <code>$(escape_html "$DB_NAME")</code>
📏 Размер: <b>${size_h}</b>
📅 $(date +'%d.%m.%Y %H:%M')${upd}"

    if (( size_bytes > TG_MAX_UPLOAD_MB * 1024 * 1024 )); then
        tg_send "$notify_to" "$(limits_instruction upload "$size_h" "$file")" "$(kb_remna)" "$thread" > /dev/null
    else
        local sent
        sent=$(tg_doc "$notify_to" "$file" "$caption" "$thread")
        if ! tg_ok "$sent"; then
            sent=$(tg_doc "$notify_to" "$file" "" "$thread")
        fi
        if ! tg_ok "$sent"; then
            tg_send "$notify_to" "⚠️ Дамп создан, но Telegram не принял файл.
📂 На сервере: <code>$(escape_html "$file")</code>
Забрать: <code>scp root@IP:$file .</code>${note}" "$(kb_remna)" "$thread" > /dev/null
        fi
    fi

    if [[ -n "$status_id" ]]; then
        tg_edit "$notify_to" "$status_id" "✅ <b>Готово</b>
➖➖➖➖➖
📂 <code>$(escape_html "${file##*/}")</code>
📏 ${size_h}${note}" "$(kb_remna)"
    fi

    log "экспорт: $file ($size_h)"
    return 0
}

pending_file_path() {
    local p="$STATE_DIR/pending_import_$1"
    [[ -f "$p" ]] && head -n 1 "$p" 2>/dev/null
}

pending_clear() {
    local uid="$1" preserve="${2:-}" p="$STATE_DIR/pending_import_$1"
    if [[ -f "$p" ]]; then
        local f
        f=$(head -n 1 "$p" 2>/dev/null)
        if [[ "$preserve" != "keep" && -n "$f" && -f "$f" ]]; then
            rm -f "$f"
        fi
        rm -f "$p"
    fi
    return 0
}

flow_import_prompt() {
    local chat_id="$1" thread="$2"
    tg_send "$chat_id" "📥 <b>Импорт базы Remnawave</b>
➖➖➖➖➖
Пришлите файл: <code>.sql.gz</code>, <code>.sql</code> или <code>.zip</code>
📉 До ${TG_MAX_DOWNLOAD_MB} МБ (лимит Telegram)

Проверю файл: заголовок pg_dump, таблицы Remnawave, опасные команды.
Мусор и чужие дампы отклоню." "$(kb_remna)" "$thread" > /dev/null
}

flow_import_denied_reason() {
    local chat_id="$1" thread="$2" reason="$3"
    tg_send "$chat_id" "❌ <b>Файл отклонён</b>
➖➖➖➖➖
$(escape_html "$reason")

Попробуйте другой дамп: <code>.sql.gz</code> из этой же панели." "$(kb_remna)" "$thread" > /dev/null
}

handle_document() {
    local chat_id="$1" thread="$2" uid="$3" doc_id="$4" doc_name="$5" doc_size="${6:-0}"

    if [[ "$chat_id" == -* ]]; then
        tg_send "$uid" "📥 Файлы для импорта принимаю только в личке." "$(kb_remna)" > /dev/null
        return 0
    fi

    [[ "$doc_size" =~ ^[0-9]+$ ]] || doc_size=0

    if (( doc_size > TG_MAX_DOWNLOAD_MB * 1024 * 1024 )); then
        local size_h
        size_h=$(awk -v b="$doc_size" 'BEGIN{printf "%.1f МБ", b/1048576}')
        tg_send "$chat_id" "$(limits_instruction download "$size_h" "")" "$(kb_remna)" "$thread" > /dev/null
        return 0
    fi

    local name_lower="${doc_name,,}"
    case "$name_lower" in
        *.sql|*.sql.gz|*.gz|*.zip) ;;
        *)
            flow_import_denied_reason "$chat_id" "$thread" "нужен .sql, .sql.gz или .zip, а пришло: ${doc_name:-без имени}"
            return 0
            ;;
    esac

    mkdir -p "$IMPORT_DIR" "$STATE_DIR" 2>/dev/null

    local status_json status_id
    status_json=$(tg_send "$chat_id" "⏳ <b>Скачиваю и проверяю файл…</b>" "" "$thread")
    status_id="$(msg_id_of "$status_json")"

    local info remote_path
    info=$(tg_call getFile --data-urlencode "file_id=$doc_id")
    remote_path=$(printf '%s' "$info" | jq -r '.result.file_path // empty' 2>/dev/null)
    if [[ -z "$remote_path" ]]; then
        local err
        err=$(tg_error_of "$info")
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ Не удалось скачать: $(escape_html "$err")" "$(kb_remna)"
        return 0
    fi

    local ts local_file suffix
    case "$name_lower" in
        *.sql.gz) suffix=".sql.gz" ;;
        *.sql) suffix=".sql" ;;
        *.gz) suffix=".gz" ;;
        *.zip) suffix=".zip" ;;
    esac
    ts="$(date +%Y%m%d_%H%M%S)"
    if ! local_file=$(mktemp "${IMPORT_DIR}/${ts}_${uid}_XXXXXX${suffix}"); then
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ Не удалось создать уникальный файл для импорта" "$(kb_remna)"
        return 0
    fi

    if ! curl -s --max-time 600 -o "$local_file" "https://api.telegram.org/file/bot${BOT_TOKEN}/${remote_path}"; then
        rm -f "$local_file"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ Скачивание прервалось. Пришлите файл ещё раз." "$(kb_remna)"
        return 0
    fi

    if [[ ! -s "$local_file" ]]; then
        rm -f "$local_file"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ Пришёл пустой файл." "$(kb_remna)"
        return 0
    fi

    local real_size
    real_size=$(bytes_of "$local_file")
    if (( real_size > TG_MAX_DOWNLOAD_MB * 1024 * 1024 )); then
        local downloaded_size
        downloaded_size=$(human_size "$local_file")
        rm -f "$local_file"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "$(limits_instruction download "$downloaded_size" "")" "$(kb_remna)"
        return 0
    fi

    if ! validate_dump "$local_file"; then
        local reason="$VD_REASON"
        cleanup_vd
        rm -f "$local_file"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ <b>Файл отклонён</b>
➖➖➖➖➖
$(escape_html "$reason")" "$(kb_remna)"
        return 0
    fi

    local tables_count
    tables_count=$(printf '%s' "$VD_TABLES" | wc -w | tr -d ' ')
    cleanup_vd

    pending_clear "$uid"
    if ! printf '%s\n' "$local_file" > "$STATE_DIR/pending_import_${uid}"; then
        cleanup_vd
        rm -f "$local_file"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ Не удалось сохранить состояние импорта" "$(kb_remna)"
        return 0
    fi

    local summary
    summary="✅ <b>Файл проверен</b>
➖➖➖➖➖
📂 <code>$(escape_html "$doc_name")</code>
📏 $(human_size "$local_file")
🧩 Тип: <b>${VD_TYPE}</b>
🗄 Таблиц Remnawave: <b>${tables_count}</b>
📥 COPY-блоков: <b>${VD_COPY}</b>${VD_PGVERSION:+
🐘 PostgreSQL: ${VD_PGVERSION}}
🛡 Опасных команд: нет"

    [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "$summary" "$(kb_remna)"

    tg_send "$chat_id" "⚠️ <b>Подтвердите импорт</b>
➖➖➖➖➖
База будет перезаписана данными из файла.

Что сделаю:
1️⃣ страховочный дамп текущей БД
2️⃣ остановлю панель
3️⃣ восстановлю базу
4️⃣ подниму панель и проверю health

Если панель не оживёт — верну страховочный дамп." "$(kb_import_confirm)" "$thread" > /dev/null
    return 0
}

flow_import_run() {
    local chat_id="$1" thread="$2" uid="$3"

    local pending
    pending="$(pending_file_path "$uid")"
    if [[ -z "$pending" || ! -f "$pending" ]]; then
        tg_send "$chat_id" "⚠️ Файл не найден — пришлите дамп заново." "$(kb_remna)" "$thread" > /dev/null
        return 0
    fi

    local status_json status_id
    status_json=$(tg_send "$chat_id" "⏳ <b>Импорт запущен</b>
➖➖➖➖➖
1/4 проверка
2/4 страховочный дамп
3/4 восстановление
4/4 запуск панели" "" "$thread")
    status_id="$(msg_id_of "$status_json")"

    if ! validate_dump "$pending"; then
        local reason="$VD_REASON"
        cleanup_vd
        pending_clear "$uid"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ <b>Импорт отменён</b>
➖➖➖➖➖
$(escape_html "$reason")" "$(kb_remna)"
        return 0
    fi
    local sql="$VD_SQL"

    if ! db_running; then
        cleanup_vd; pending_clear "$uid"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ Контейнер БД <code>$(escape_html "$DB_CONTAINER")</code> не запущен." "$(kb_remna)"
        return 0
    fi

    if ! mkdir -p "$SAFETY_DIR"; then
        cleanup_vd
        pending_clear "$uid"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ Не удалось создать каталог страховочных дампов" "$(kb_remna)"
        return 0
    fi
    local ts safety
    ts="$(date +%Y-%m-%d_%H_%M_%S)"
    safety="$SAFETY_DIR/pre_restore_${ts}.sql.gz"

    if ! dump_to_file "$safety" "$STATE_DIR/safety.err"; then
        cleanup_vd; pending_clear "$uid"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ <b>Импорт отменён</b>
➖➖➖➖➖
Не удалось сделать страховочный дамп — база не тронута." "$(kb_remna)"
        return 0
    fi

    local sql_copy="$STATE_DIR/import_${ts}.sql"
    if ! cp -f "$sql" "$sql_copy" 2>/dev/null; then
        cleanup_vd
        pending_clear "$uid"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ Не удалось подготовить SQL для восстановления" "$(kb_remna)"
        return 0
    fi

    RESTORE_ROLLED_BACK=0
    RESTORE_ERRORS=0
    local ok=0
    restore_sql_file "$sql_copy" "" "$safety" && ok=1

    cleanup_vd

    if (( ok == 1 )); then
        pending_clear "$uid" keep
        local moved="$BACKUP_DIR/rw_db_backup_imported_${ts}.sql.gz"
        if [[ "$pending" == *.gz ]]; then
            mv -f "$pending" "$moved" 2>/dev/null || moved=""
        else
            if gzip -9 -c "$sql_copy" > "$moved" 2>/dev/null; then
                rm -f "$pending"
            else
                rm -f "$moved"
                moved=""
            fi
        fi
        rm -f "$sql_copy"
        apply_retention "$KEEP_FILES"

        local archive_note=""
        [[ -n "$moved" ]] || archive_note=$'\n\n⚠️ SQL восстановлен, но исходный файл не удалось переместить в архив.'
        local upd
        upd="$(update_line)"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "✅ <b>Импорт выполнен</b>
➖➖➖➖➖
🗄 БД: <code>$(escape_html "$DB_NAME")</code>
🖥 Панель: <b>healthy</b>
⚠️ Ошибок при заливке: ${RESTORE_ERRORS}
🛡 Страховочный дамп: <code>$(escape_html "${safety##*/}")</code>${archive_note}${upd}" "$(kb_remna)"

        notify_chat_text "✅ <b>Импорт БД Remnawave</b>
➖➖➖➖➖
Выполнил админ <code>${uid}</code>
📂 <code>$(escape_html "$(basename "$pending" 2>/dev/null)")</code>"
        if [[ -n "$moved" ]]; then
            log "импорт выполнен, файл: $moved"
        else
            log "импорт выполнен, но архив не перемещён; исходный файл: $pending"
        fi
    else
        rm -f "$sql_copy"
        pending_clear "$uid"
        local rolled="нет"
        (( RESTORE_ROLLED_BACK == 1 )) && rolled="да — база восстановлена из страховочного дампа"
        [[ -n "$status_id" ]] && tg_edit "$chat_id" "$status_id" "❌ <b>Импорт не удался</b>
➖➖➖➖➖
Ошибок psql: ${RESTORE_ERRORS}
🛡 Откат: <b>${rolled}</b>

Проверьте панель: <code>docker logs --tail 50 $(escape_html "$PANEL_CONTAINER")</code>" "$(kb_remna)"
        notify_chat_text "⚠️ <b>Импорт БД не удался</b>
➖➖➖➖➖
Админ <code>${uid}</code> · откат: ${rolled}"
        log "импорт не удался (ошибок psql: $RESTORE_ERRORS, откат: $rolled)"
    fi

    return 0
}

flow_list() {
    local chat_id="$1" thread="$2"
    local files=()
    mapfile -t files < <(list_backups)

    if [[ ${#files[@]} -eq 0 ]]; then
        tg_send "$chat_id" "📦 <b>Архивов пока нет</b>
➖➖➖➖➖
Нажмите «Экспорт» — сделаю первый." "$(kb_remna)" "$thread" > /dev/null
        return 0
    fi

    local text="📦 <b>Архивы на сервере</b>
➖➖➖➖➖
" rows="" row="" in_row=0 i=1 f

    for f in "${files[@]}"; do
        local sz dt
        sz=$(human_size "$f")
        dt=$(date -r "$f" +'%d.%m %H:%M' 2>/dev/null)
        text+="${i}. <code>$(escape_html "${f##*/}")</code>
     ${sz} · ${dt}
"
        row+="{\"text\":\"⬇️ #${i}\",\"callback_data\":\"r:dl:${i}\"},"
        in_row=$((in_row + 1))
        if (( in_row == 4 )); then
            rows+="[${row%,}],"
            row=""; in_row=0
        fi
        i=$((i + 1))
        (( i > 12 )) && break
    done
    [[ -n "$row" ]] && rows+="[${row%,}],"

    local keyboard="{\"inline_keyboard\":[${rows}[{\"text\":\"⬅️ Назад\",\"callback_data\":\"m:remna\"}]]}"
    tg_send "$chat_id" "$text" "$keyboard" "$thread" > /dev/null
    return 0
}

flow_send_archive() {
    local chat_id="$1" thread="$2" index="$3"
    local files=()
    mapfile -t files < <(list_backups)

    if ! [[ "$index" =~ ^[0-9]+$ ]] || (( index < 1 || index > ${#files[@]} )); then
        tg_send "$chat_id" "⚠️ Архив не найден — обновите список." "$(kb_remna)" "$thread" > /dev/null
        return 0
    fi

    local f="${files[$((index - 1))]}" size
    size=$(bytes_of "$f")
    if (( size > TG_MAX_UPLOAD_MB * 1024 * 1024 )); then
        tg_send "$chat_id" "$(limits_instruction upload "$(human_size "$f")" "$f")" "$(kb_remna)" "$thread" > /dev/null
        return 0
    fi

    local upd sent
    upd="$(update_line)"
    sent=$(tg_doc "$chat_id" "$f" "💎 <b>$(escape_html "${f##*/}")</b>
➖➖➖➖➖
📏 $(human_size "$f")
📅 $(date -r "$f" +'%d.%m.%Y %H:%M')${upd}" "$thread")
    if ! tg_ok "$sent"; then
        sent=$(tg_doc "$chat_id" "$f" "" "$thread")
    fi
    if ! tg_ok "$sent"; then
        tg_send "$chat_id" "⚠️ Не удалось отправить архив: $(escape_html "$(tg_error_of "$sent")")
📂 <code>$(escape_html "$f")</code>" "$(kb_remna)" "$thread" > /dev/null
    fi
    return 0
}

await_set() {
    mkdir -p "$STATE_DIR" 2>/dev/null
    printf '%s|%s\n' "$2" "${3:-}" > "$STATE_DIR/await_$1"
}

await_get() {
    local f="$STATE_DIR/await_$1"
    [[ -f "$f" ]] && head -n 1 "$f" 2>/dev/null
}

await_clear() {
    rm -f "$STATE_DIR/await_$1" 2>/dev/null
    return 0
}

cron_remove() {
    cron_apply 0
}

cron_apply() {
    local hours="$1"
    if ! command -v crontab > /dev/null 2>&1; then
        (( hours <= 0 )) && return 0
        return 1
    fi
    local line="0 * * * * /bin/bash $INSTALL_DIR/rw-back-bot.sh cron >> /var/log/rw-back-cron.log 2>&1"
    local tmp rc listing
    listing=$(crontab -l 2>&1)
    rc=$?
    if (( rc != 0 )); then
        if grep -qi 'no crontab for' <<< "$listing"; then
            listing=""
        else
            log "не удалось прочитать crontab — существующие задачи не изменены"
            return 1
        fi
    fi
    tmp="$(mktemp)" || return 1
    printf '%s\n' "$listing" | grep -v 'rw-back-bot.sh cron' > "$tmp"
    rc=$?
    if (( rc > 1 )); then
        rm -f "$tmp"
        return 1
    fi
    if (( hours > 0 )); then
        if ! grep -q '^SHELL=' "$tmp"; then
            printf 'SHELL=/bin/bash\n' | cat - "$tmp" > "$tmp.2" && mv -f "$tmp.2" "$tmp" || { rm -f "$tmp" "$tmp.2"; return 1; }
        fi
        if ! grep -q '^PATH=' "$tmp"; then
            printf 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' | cat - "$tmp" > "$tmp.2" && mv -f "$tmp.2" "$tmp" || { rm -f "$tmp" "$tmp.2"; return 1; }
        fi
        printf '%s\n' "$line" >> "$tmp" || { rm -f "$tmp" "$tmp.2"; return 1; }
    fi
    crontab "$tmp" 2>/dev/null
    rc=$?
    rm -f "$tmp" "$tmp.2"
    return "$rc"
}

send_main_menu() {
    local chat_id="$1" thread="$2" edit_id="${3:-}"
    if [[ -n "$edit_id" ]]; then
        tg_edit "$chat_id" "$edit_id" "$(start_text)" "$KB_MAIN"
    else
        tg_send "$chat_id" "$(start_text)" "$KB_MAIN" "$thread" > /dev/null
    fi
}

handle_update() {
    local raw="$1" parsed kind uid chat_id thread text cb_id cb_data msg_id doc_id doc_name doc_size

    parsed=$(printf '%s' "$raw" | jq -r '[
        (if .message then "message" elif .callback_query then "callback" else "" end),
        (.message.from.id // .callback_query.from.id // ""),
        (.message.chat.id // .callback_query.message.chat.id // ""),
        (.message.message_thread_id // .callback_query.message.message_thread_id // ""),
        (.message.text // ""),
        (.callback_query.id // ""),
        (.callback_query.data // ""),
        (.callback_query.message.message_id // ""),
        (.message.document.file_id // ""),
        (.message.document.file_name // ""),
        (.message.document.file_size // 0)
    ] | map(tostring) | join("\u001f")' 2>/dev/null)

    [[ -z "$parsed" ]] && return 0
    IFS=$'\x1f' read -r kind uid chat_id thread text cb_id cb_data msg_id doc_id doc_name doc_size <<< "$parsed"

    [[ -z "$kind" || -z "$chat_id" || -z "$uid" ]] && return 0

    if ! is_admin "$uid"; then
        if [[ "$(admin_count)" -eq 0 ]]; then
            handle_binding "$kind" "$chat_id" "$thread" "$uid" "$text" "$cb_id"
        else
            log "отказ: user_id=$uid chat_id=$chat_id"
        fi
        return 0
    fi

    if [[ "$kind" == "message" ]]; then
        if [[ -n "$doc_id" ]]; then
            handle_document "$chat_id" "$thread" "$uid" "$doc_id" "$doc_name" "$doc_size"
            return 0
        fi
        [[ -z "$text" ]] && return 0

        local cmd
        cmd=$(printf '%s' "$text" | head -n 1 | tr '[:upper:]' '[:lower:]' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        cmd="${cmd%%@*}"

        local awaiting
        awaiting="$(await_get "$uid")"
        if [[ -n "$awaiting" ]]; then
            local act
            act="${awaiting%%|*}"
            case "$act" in
                add_admin)
                    local clean
                    clean=$(printf '%s' "$text" | tr -d '[:space:]')
                    await_clear "$uid"
                    add_admin_by_input "$chat_id" "$thread" "$uid" "$clean"
                    return 0
                    ;;
                set_hours)
                    local hours
                    hours=$(printf '%s' "$text" | tr -d '[:space:]')
                    await_clear "$uid"
                    apply_schedule "$chat_id" "$thread" "$hours"
                    return 0
                    ;;
                set_keep)
                    local keep
                    keep=$(printf '%s' "$text" | tr -d '[:space:]')
                    await_clear "$uid"
                    apply_keep "$chat_id" "$thread" "$keep"
                    return 0
                    ;;
            esac
        fi

        case "$cmd" in
            /start|/menu|start|menu|меню|/help|help)
                send_main_menu "$chat_id" "$thread"
                ;;
            /remna|remna|remnawave|бэкап|backup)
                tg_send "$chat_id" "$(remna_text)" "$(kb_remna)" "$thread" > /dev/null
                ;;
            /settings|settings|настройки)
                tg_send "$chat_id" "$(settings_text)" "$(kb_settings)" "$thread" > /dev/null
                ;;
            /export|export|экспорт)
                flow_export "$chat_id" "$thread" "$uid"
                ;;
            /import|import|импорт)
                if [[ "$chat_id" == -* ]]; then
                    tg_send "$uid" "📥 Импорт — только в личке." "$(kb_remna)" > /dev/null
                else
                    flow_import_prompt "$chat_id" "$thread"
                fi
                ;;
            /list|list|бэкапы)
                flow_list "$chat_id" "$thread"
                ;;
            /cancel|отмена)
                pending_clear "$uid"
                await_clear "$uid"
                tg_send "$chat_id" "↩️ Отменено." "$(kb_remna)" "$thread" > /dev/null
                ;;
            *)
                send_main_menu "$chat_id" "$thread"
                ;;
        esac
        return 0
    fi

    tg_answer "$cb_id"

    case "$cb_data" in
        m:main) send_main_menu "$chat_id" "$thread" "$msg_id" ;;
        m:remna) tg_edit "$chat_id" "$msg_id" "$(remna_text)" "$(kb_remna)" ;;
        m:settings) tg_edit "$chat_id" "$msg_id" "$(settings_text)" "$(kb_settings)" ;;

        r:export) flow_export "$chat_id" "$thread" "$uid" ;;
        r:import)
            if [[ "$chat_id" == -* ]]; then
                tg_send "$uid" "📥 Импорт — только в личке." "$(kb_remna)" > /dev/null
            else
                flow_import_prompt "$chat_id" "$thread"
            fi
            ;;
        r:list) flow_list "$chat_id" "$thread" ;;
        r:dl:*) flow_send_archive "$chat_id" "$thread" "${cb_data#r:dl:}" ;;

        s:menu) tg_edit "$chat_id" "$msg_id" "$(settings_text)" "$(kb_settings)" ;;
        s:admins) tg_edit "$chat_id" "$msg_id" "$(admins_text)" "$(kb_admins)" ;;
        s:schedule) tg_edit "$chat_id" "$msg_id" "$(schedule_text)" "$(kb_schedule)" ;;
        s:keep) tg_edit "$chat_id" "$msg_id" "$(keep_text)" "$(kb_keep)" ;;

        a:add)
            await_set "$uid" "add_admin" ""
            tg_edit "$chat_id" "$msg_id" "➕ <b>Новый админ</b>
➖➖➖➖➖
Пришлите <b>ID</b> или <b>@username</b>.

ID можно узнать в @userinfobot.
Отмена — /cancel" "$(kb_admins)"
            ;;
        a:del)
            local del_kb="" ids id
            local -a arr=()
            ids="$(normalize_ids "$BOT_ADMIN_IDS")"
            if [[ -z "$ids" ]]; then
                tg_edit "$chat_id" "$msg_id" "👥 Список пуст." "$(kb_admins)"
                return 0
            fi
            IFS=',' read -ra arr <<< "$ids"
            for id in "${arr[@]}"; do
                del_kb+="{\"text\":\"🗑 ${id}\",\"callback_data\":\"a:rm:${id}\"},"
            done
            tg_edit "$chat_id" "$msg_id" "🗑 <b>Кого убрать?</b>" "{\"inline_keyboard\":[[${del_kb%,}],[{\"text\":\"⬅️ Назад\",\"callback_data\":\"s:admins\"}]]}"
            ;;
        a:rm:*)
            local remove_id="${cb_data#a:rm:}"
            if [[ "$(admin_count)" -le 1 ]]; then
                tg_edit "$chat_id" "$msg_id" "⚠️ Нельзя удалить последнего админа — бот станет неуправляемым." "$(kb_admins)"
                return 0
            fi
            local new_ids old_ids="$BOT_ADMIN_IDS"
            if ! new_ids=$(printf '%s' "$(normalize_ids "$BOT_ADMIN_IDS")" | tr ',' '\n' | grep -v -x -- "$remove_id" | paste -sd, -) || [[ -z "$new_ids" ]]; then
                tg_edit "$chat_id" "$msg_id" "❌ Не удалось изменить список админов — исходный список сохранён." "$(kb_admins)"
                return 0
            fi
            if [[ "$new_ids" == "$(normalize_ids "$old_ids")" ]]; then
                tg_edit "$chat_id" "$msg_id" "⚠️ Админ <code>${remove_id}</code> не найден." "$(kb_admins)"
                return 0
            fi
            BOT_ADMIN_IDS="$new_ids"
            if ! save_config; then
                BOT_ADMIN_IDS="$old_ids"
                tg_edit "$chat_id" "$msg_id" "❌ Не удалось сохранить список админов." "$(kb_admins)"
                return 0
            fi
            tg_edit "$chat_id" "$msg_id" "✅ Админ <code>${remove_id}</code> удалён.

$(admins_text)" "$(kb_admins)"
            ;;

        h:0)
            apply_schedule "$chat_id" "$thread" 0 "$msg_id"
            ;;
        h:custom)
            await_set "$uid" "set_hours" ""
            tg_edit "$chat_id" "$msg_id" "🕒 <b>Свой интервал</b>
➖➖➖➖➖
Пришлите число часов (1–168)." "$(kb_schedule)"
            ;;
        h:*)
            apply_schedule "$chat_id" "$thread" "${cb_data#h:}" "$msg_id"
            ;;
        k:custom)
            await_set "$uid" "set_keep" ""
            tg_edit "$chat_id" "$msg_id" "📦 <b>Своё значение</b>
➖➖➖➖➖
Сколько архивов хранить (1–200)?" "$(kb_keep)"
            ;;
        k:*)
            apply_keep "$chat_id" "$thread" "${cb_data#k:}" "$msg_id"
            ;;

        i:yes) flow_import_run "$chat_id" "$thread" "$uid" ;;
        i:no)
            pending_clear "$uid"
            tg_edit "$chat_id" "$msg_id" "❌ <b>Импорт отменён</b>
➖➖➖➖➖
База не тронута." "$(kb_remna)"
            ;;

        *) send_main_menu "$chat_id" "$thread" "$msg_id" ;;
    esac

    return 0
}

apply_schedule() {
    local chat_id="$1" thread="$2" hours="$3" edit_id="${4:-}" old_hours="$CRON_HOURS"
    [[ "$hours" =~ ^[0-9]{1,3}$ ]] || {
        tg_send "$chat_id" "⚠️ Нужно число часов." "$(kb_schedule)" "$thread" > /dev/null
        return 0
    }
    hours=$((10#$hours))
    if (( hours < 0 || hours > 168 )); then
        tg_send "$chat_id" "⚠️ Допустимо от 1 до 168 часов или 0 — выключить." "$(kb_schedule)" "$thread" > /dev/null
        return 0
    fi

    CRON_HOURS="$hours"
    if ! cron_apply "$hours"; then
        CRON_HOURS="$old_hours"
        tg_send "$chat_id" "❌ Не удалось записать cron. Прежнее расписание сохранено." "$(kb_schedule)" "$thread" > /dev/null
        return 0
    fi
    if ! save_config; then
        CRON_HOURS="$old_hours"
        cron_apply "$old_hours" > /dev/null 2>&1 || true
        tg_send "$chat_id" "❌ Не удалось сохранить расписание в конфигурацию." "$(kb_schedule)" "$thread" > /dev/null
        return 0
    fi

    local text="📴 <b>Автобэкап выключен</b>"
    if (( hours > 0 )); then
        text="✅ <b>Расписание обновлено</b>
➖➖➖➖➖
⏰ Каждые <b>${hours} ч</b>
📥 Дамп придёт в личку админам"
    fi

    if [[ -n "$edit_id" ]]; then
        tg_edit "$chat_id" "$edit_id" "$text" "$(kb_schedule)"
    else
        tg_send "$chat_id" "$text" "$(kb_schedule)" "$thread" > /dev/null
    fi
    return 0
}

apply_keep() {
    local chat_id="$1" thread="$2" value="$3" edit_id="${4:-}"
    [[ "$value" =~ ^[0-9]{1,3}$ ]] || {
        tg_send "$chat_id" "⚠️ Нужно число." "$(kb_keep)" "$thread" > /dev/null
        return 0
    }
    value=$((10#$value))
    if (( value < 1 || value > 200 )); then
        tg_send "$chat_id" "⚠️ Допустимо от 1 до 200." "$(kb_keep)" "$thread" > /dev/null
        return 0
    fi

    local old_keep="$KEEP_FILES"
    KEEP_FILES="$value"
    if ! save_config; then
        KEEP_FILES="$old_keep"
        tg_send "$chat_id" "❌ Не удалось сохранить лимит в конфигурацию." "$(kb_keep)" "$thread" > /dev/null
        return 0
    fi
    apply_retention "$value"

    local text="✅ <b>Хранение обновлено</b>
➖➖➖➖➖
📦 Оставляю <b>${value}</b> последних архивов"

    if [[ -n "$edit_id" ]]; then
        tg_edit "$chat_id" "$edit_id" "$text" "$(kb_keep)"
    else
        tg_send "$chat_id" "$text" "$(kb_keep)" "$thread" > /dev/null
    fi
    return 0
}

add_admin_by_input() {
    local chat_id="$1" thread="$2" uid="$3" input="$4"

    [[ -z "$input" ]] && { tg_send "$chat_id" "⚠️ Пустое значение." "$(kb_admins)" "$thread" > /dev/null; return 0; }

    local new_id=""

    if [[ "$input" =~ ^[0-9]{5,20}$ ]]; then
        new_id="$input"
    elif [[ "$input" =~ ^@?[A-Za-z0-9_]{4,32}$ ]]; then
        local username="${input#@}"
        local resp
        resp=$(tg_call getChat --data-urlencode "chat_id=@${username}")
        new_id=$(printf '%s' "$resp" | jq -r 'if .result.type == "private" then (.result.id // empty) else empty end' 2>/dev/null)
        if [[ ! "$new_id" =~ ^[0-9]{5,20}$ ]]; then
            tg_send "$chat_id" "❌ Не нашёл пользователя @${username}.
Пусть человек нажмёт /start у бота, затем добавьте по ID." "$(kb_admins)" "$thread" > /dev/null
            return 0
        fi
    else
        tg_send "$chat_id" "❌ Нужен ID (цифры) или @username." "$(kb_admins)" "$thread" > /dev/null
        return 0
    fi

    local ids
    ids="$(normalize_ids "$BOT_ADMIN_IDS")"
    if [[ ",$ids," == *",${new_id},"* ]]; then
        tg_send "$chat_id" "ℹ️ <code>${new_id}</code> уже админ." "$(kb_admins)" "$thread" > /dev/null
        return 0
    fi

    BOT_ADMIN_IDS="$(normalize_ids "${ids:+$ids,}${new_id}")"
    if ! save_config; then
        BOT_ADMIN_IDS="$ids"
        tg_send "$chat_id" "❌ Не удалось сохранить админа в конфигурацию." "$(kb_admins)" "$thread" > /dev/null
        return 0
    fi

    tg_send "$chat_id" "✅ Админ <code>${new_id}</code> добавлен.

$(admins_text)" "$(kb_admins)" "$thread" > /dev/null
    return 0
}

serve() {
    if [[ -z "${BOT_TOKEN:-}" ]]; then
        print_message "WARN" "Telegram не настроен: BOT_TOKEN пуст. Служба остановлена без перезапуска."
        print_message "INFO" "Настроить: rw-back → Telegram-бот"
        return 0
    fi
    require_deps || die "Нужны curl, jq, gzip. Установите: apt-get install -y curl jq gzip"

    mkdir -p "$BACKUP_DIR" "$STATE_DIR" "$IMPORT_DIR" || die "Не удалось создать рабочие каталоги"
    chmod 700 "$INSTALL_DIR" "$STATE_DIR" "$BACKUP_DIR" 2>/dev/null || true
    if command -v flock > /dev/null 2>&1; then
        exec 8> "$STATE_DIR/serve.lock" || die "Не удалось открыть serve.lock"
        flock -n 8 || die "Бот уже запущен. Остановите службу или другой консольный экземпляр."
    else
        log "flock не найден — защита от второго экземпляра недоступна"
    fi
    if (( CRON_HOURS > 0 )); then
        cron_apply "$CRON_HOURS" || log "не удалось обновить cron-расписание"
    fi

    local me username="bot"
    me=$(tg_call getMe)
    if [[ -z "$me" ]]; then
        print_message "WARN" "Telegram пока недоступен. Бот будет повторять подключение автоматически."
    else
        tg_ok "$me" || die "Telegram не принял токен: $(tg_error_of "$me")"
        username=$(printf '%s' "$me" | jq -r '.result.username // "bot"' 2>/dev/null)
    fi

    local hook hook_url
    hook=$(tg_call getWebhookInfo)
    hook_url=$(printf '%s' "$hook" | jq -r '.result.url // empty' 2>/dev/null)
    if [[ -n "$hook_url" ]]; then
        log "найден webhook ${hook_url} — сбрасываю для long polling"
        tg_call deleteWebhook > /dev/null 2>&1 || log "не удалось сбросить webhook"
    fi

    if [[ "$(admin_count)" -eq 0 ]]; then
        if [[ -n "$(setup_code_current)" ]]; then
            print_message "INFO" "Режим привязки: жду код из установщика"
        else
            print_message "WARN" "Админы не заданы. Код привязки: rw-back admin-code"
        fi
    fi

    print_message "SUCCESS" "Бот @${username} запущен · v${LOCAL_VERSION} · админов: $(admin_count)"

    local offset=0
    [[ -f "$STATE_DIR/offset" ]] && offset=$(cat "$STATE_DIR/offset" 2>/dev/null || echo 0)
    [[ "$offset" =~ ^[0-9]+$ ]] || offset=0

    while true; do
        load_config
        if [[ -z "${BOT_TOKEN:-}" ]]; then
            print_message "WARN" "BOT_TOKEN удалён из конфигурации. Останавливаю службу без цикла ошибок."
            return 0
        fi
        local response
        response=$(curl -s --max-time 70 "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" \
            --data-urlencode "offset=$offset" \
            --data-urlencode "timeout=30" \
            --data-urlencode 'allowed_updates=["message","callback_query"]' 2>/dev/null) || true

        if [[ -z "$response" ]]; then
            sleep 3
            continue
        fi
        if ! tg_ok "$response"; then
            local error_code retry_after
            error_code=$(printf '%s' "$response" | jq -r '.error_code // 0' 2>/dev/null)
            case "$error_code" in
                401|404)
                    log "getUpdates: токен отклонён Telegram ($(tg_error_of "$response")). Останавливаю процесс."
                    return 1
                    ;;
                409)
                    log "getUpdates: конфликт второго polling-экземпляра. Останавливаю процесс."
                    return 1
                    ;;
                429)
                    retry_after=$(printf '%s' "$response" | jq -r '.parameters.retry_after // 5' 2>/dev/null)
                    [[ "$retry_after" =~ ^[0-9]+$ ]] || retry_after=5
                    log "getUpdates: лимит Telegram, пауза $retry_after с"
                    sleep "$retry_after"
                    continue
                    ;;
            esac
            log "getUpdates: $(tg_error_of "$response")"
            sleep 5
            continue
        fi

        local count
        count=$(printf '%s' "$response" | jq '.result | length' 2>/dev/null)
        [[ "$count" =~ ^[0-9]+$ ]] || count=0

        if (( count > 0 )); then
            local update_id next_offset
            while IFS= read -r upd; do
                if (
                    exec 9> "$STATE_DIR/ops.lock" 2>/dev/null || exit 1
                    if command -v flock > /dev/null 2>&1; then
                        flock -w 30 9 || { log "не дождался ops.lock — апдейт вернётся в очередь"; exit 1; }
                    fi
                    load_config
                    [[ -n "${BOT_TOKEN:-}" ]] || exit 1
                    handle_update "$upd"
                ); then
                    update_id=$(printf '%s' "$upd" | jq -r '.update_id // empty' 2>/dev/null)
                    [[ "$update_id" =~ ^[0-9]+$ ]] || { log "update без корректного update_id"; return 1; }
                    next_offset=$((update_id + 1))
                    if ! printf '%s\n' "$next_offset" > "$STATE_DIR/offset.tmp" || ! mv -f "$STATE_DIR/offset.tmp" "$STATE_DIR/offset"; then
                        log "не удалось сохранить offset — процесс остановлен во избежание повторных операций"
                        return 1
                    fi
                    offset="$next_offset"
                else
                    log "апдейт не обработан — следующий poll начнётся с него, предыдущие не повторятся"
                    break
                fi
            done < <(printf '%s' "$response" | jq -c '.result[]' 2>/dev/null)
        fi
    done
}

cmd_cron() {
    require_deps || die "нет зависимостей"

    mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$SAFETY_DIR" "$IMPORT_DIR" 2>/dev/null

    exec 9> "$STATE_DIR/ops.lock"
    flock -w 300 9 || die "операция уже выполняется"

    (( CRON_HOURS > 0 )) || { log "расписание выключено — выхожу"; return 0; }
    local now last=0 interval
    now=$(date +%s)
    if [[ -f "$STATE_DIR/cron_last_run" ]]; then
        last=$(head -n 1 "$STATE_DIR/cron_last_run" 2>/dev/null)
        [[ "$last" =~ ^[0-9]+$ ]] || last=0
    fi
    interval=$((CRON_HOURS * 3600))
    if (( last > 0 && now - last < interval )); then
        log "интервал ${CRON_HOURS} ч ещё не истёк — пропускаю запуск"
        return 0
    fi
    db_running || die "контейнер БД не запущен"

    local ts file
    ts="$(date +%Y-%m-%d_%H_%M_%S)"
    file="$BACKUP_DIR/rw_db_backup_${ts}.sql.gz"

    dump_to_file "$file" "$STATE_DIR/cron.err" || die "pg_dumpall вернул ошибку"
    apply_retention "$KEEP_FILES"
    if ! printf '%s\n' "$now" > "$STATE_DIR/cron_last_run.tmp" || ! mv -f "$STATE_DIR/cron_last_run.tmp" "$STATE_DIR/cron_last_run"; then
        log "не удалось сохранить время автобэкапа — при следующем запуске возможна повторная копия"
    fi

    local size
    size=$(human_size "$file")
    local caption
    caption="🕒 <b>Автобэкап Remnawave</b>
➖➖➖➖➖
🗄 БД: <code>$(escape_html "$DB_NAME")</code>
📏 Размер: <b>${size}</b>
📅 $(date +'%d.%m.%Y %H:%M')"

    local ids uid
    local -a arr=()
    ids="$(normalize_ids "$BOT_ADMIN_IDS")"
    if [[ -z "$ids" || -z "${BOT_TOKEN:-}" ]]; then
        log "автобэкап сохранён локально: Telegram не настроен или админы не заданы"
        return 0
    fi

    IFS=',' read -ra arr <<< "$ids"
    for uid in "${arr[@]}"; do
        if (( $(bytes_of "$file") > TG_MAX_UPLOAD_MB * 1024 * 1024 )); then
            tg_send "$uid" "$(limits_instruction upload "$size" "$file")" > /dev/null 2>&1 || true
        else
            tg_doc "$uid" "$file" "$caption" > /dev/null 2>&1 || true
        fi
    done

    log "автобэкап: $file ($size)"
    return 0
}

cmd_backup() {
    load_config
    require_deps || die "нет зависимостей"
    db_running || die "контейнер БД $DB_CONTAINER не запущен"

    mkdir -p "$BACKUP_DIR"
    local ts file
    ts="$(date +%Y-%m-%d_%H_%M_%S)"
    file="$BACKUP_DIR/rw_db_backup_${ts}.sql.gz"

    print_message "INFO" "Создаю дамп…"
    dump_to_file "$file" /dev/stderr || die "не удалось создать дамп"
    apply_retention "$KEEP_FILES"
    print_message "SUCCESS" "Дамп: $file ($(human_size "$file"))"

    if [[ -n "${BOT_TOKEN:-}" ]]; then
        local ids uid
        local -a arr=()
        ids="$(normalize_ids "$BOT_ADMIN_IDS")"
        if [[ -n "$ids" ]]; then
            IFS=',' read -ra arr <<< "$ids"
            for uid in "${arr[@]}"; do
                if (( $(bytes_of "$file") > TG_MAX_UPLOAD_MB * 1024 * 1024 )); then
                    tg_send "$uid" "$(limits_instruction upload "$(human_size "$file")" "$file")" > /dev/null 2>&1 || true
                else
                    tg_doc "$uid" "$file" "💾 Ручной бэкап · $(human_size "$file")" > /dev/null 2>&1 || true
                fi
            done
        else
            print_message "INFO" "Админы не заданы — дамп сохранён только локально"
        fi
    else
        print_message "INFO" "Telegram не настроен — дамп сохранён только локально"
    fi
    return 0
}

cmd_validate() {
    load_config
    local file="${1:-}"
    [[ -n "$file" ]] || die "укажите файл: rw-back-bot.sh validate /path/dump.sql.gz"
    [[ -f "$file" ]] || die "файл не найден: $file"

    mkdir -p "$STATE_DIR"
    print_message "INFO" "Проверяю $file…"
    if validate_dump "$file"; then
        print_message "SUCCESS" "Дамп корректен"
        echo "  тип:        $VD_TYPE"
        echo "  PostgreSQL: ${VD_PGVERSION:-неизвестно}"
        echo "  таблицы:    $VD_TABLES"
        echo "  COPY:       $VD_COPY"
        cleanup_vd
        return 0
    else
        print_message "ERROR" "Файл отклонён: $VD_REASON"
        cleanup_vd
        return 1
    fi
}

cmd_restore() {
    load_config
    local file="${1:-}"
    [[ -n "$file" ]] || die "укажите файл: rw-back-bot.sh restore /path/dump.sql.gz"
    [[ -f "$file" ]] || die "файл не найден: $file"
    db_running || die "контейнер БД не запущен"

    mkdir -p "$STATE_DIR" "$SAFETY_DIR"

    exec 9> "$STATE_DIR/ops.lock"
    flock -w 60 9 || die "операция уже выполняется"

    if ! validate_dump "$file"; then
        local reason="$VD_REASON"
        cleanup_vd
        die "файл отклонён: $reason"
    fi
    local sql="$VD_SQL"

    local ts safety
    ts="$(date +%Y-%m-%d_%H_%M_%S)"
    safety="$SAFETY_DIR/pre_restore_${ts}.sql.gz"
    print_message "INFO" "Страховочный дамп…"
    dump_to_file "$safety" /dev/stderr || { cleanup_vd; die "не удалось сделать страховочный дамп"; }

    print_message "INFO" "Восстанавливаю…"
    RESTORE_ROLLED_BACK=0
    RESTORE_ERRORS=0
    if restore_sql_file "$sql" "" "$safety"; then
        cleanup_vd
        print_message "SUCCESS" "Готово. Ошибок psql: $RESTORE_ERRORS"
        return 0
    fi
    cleanup_vd
    print_message "ERROR" "Импорт не удался. Ошибок: $RESTORE_ERRORS"
    if (( RESTORE_ROLLED_BACK == 1 )); then
        print_message "WARN" "База восстановлена из страховочного дампа"
    else
        print_message "ERROR" "Откат не выполнен — основной лог: $RESTORE_LOG"
        [[ -z "${RESTORE_ROLLBACK_LOG:-}" ]] || print_message "ERROR" "Лог отката: $RESTORE_ROLLBACK_LOG"
    fi
    return 1
}

cmd_list() {
    load_config
    local files=()
    mapfile -t files < <(list_backups)
    if [[ ${#files[@]} -eq 0 ]]; then
        print_message "INFO" "Архивов нет"
        return 0
    fi
    local i=1 f
    for f in "${files[@]}"; do
        printf '%2d) %-45s %8s  %s\n' "$i" "${f##*/}" "$(human_size "$f")" "$(date -r "$f" +'%Y-%m-%d %H:%M' 2>/dev/null)"
        i=$((i + 1))
    done
    return 0
}

usage() {
    cat <<'TXT'
rw-back-bot.sh — Telegram-бот и движок бэкапов Remnawave

  rw-back-bot.sh                 слушать Telegram (служба)
  rw-back-bot.sh cron            автоматический бэкап + рассылка админам
  rw-back-bot.sh backup          ручной бэкап с отправкой в Telegram
  rw-back-bot.sh list            список архивов
  rw-back-bot.sh validate FILE   проверить дамп (без восстановления)
  rw-back-bot.sh restore FILE    восстановить БД из файла
  rw-back-bot.sh version         версия
TXT
}

main() {
    bind_version
    load_config

    local mode="${1:-serve}"
    case "$mode" in
        serve) serve ;;
        cron) cmd_cron ;;
        backup) cmd_backup ;;
        list) cmd_list ;;
        validate) shift; cmd_validate "$@" ;;
        restore) shift; cmd_restore "$@" ;;
        version) echo "$LOCAL_VERSION" ;;
        -h|--help|help) usage ;;
        *) usage; exit 1 ;;
    esac
}

main "$@"

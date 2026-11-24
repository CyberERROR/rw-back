#!/usr/bin/env bash
set -o pipefail

ui_color_capable() {
    [[ -t 1 && "${TERM:-dumb}" != "dumb" && "${RW_PLAIN_UI:-0}" != "1" && -z "${NO_COLOR:-}" ]]
}

ui_colors_init() {
    if ui_color_capable; then
        RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; CYAN=$'\e[36m'
        GRAY=$'\e[37m'; LIGHT_GRAY=$'\e[90m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
        MUTED_GREEN=$'\e[38;5;71m'; UI_SEL_BG=$'\e[48;5;22m\e[97m'
    else
        RED=""; GREEN=""; YELLOW=""; CYAN=""; GRAY=""; LIGHT_GRAY=""; BOLD=""; RESET=""
        MUTED_GREEN=""; UI_SEL_BG=""
    fi
}

ui_colors_init

SELF_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"
SELF_DIR="$(dirname "$SELF_PATH")"
SELF_IS_SCRIPT=false
if [[ -f "$SELF_PATH" ]] && head -c 2 "$SELF_PATH" 2>/dev/null | grep -q '#!' \
    && grep -q 'rw-back' "$SELF_PATH" 2>/dev/null; then
    SELF_IS_SCRIPT=true
fi

if [[ ! -t 0 && -t 1 && -e /dev/tty && -z "${RW_BACK_EXECED:-}" ]]; then
    export RW_BACK_EXECED=1
    if [[ "$SELF_IS_SCRIPT" == true && -r "$SELF_PATH" ]]; then
        exec bash "$SELF_PATH" "$@" < /dev/tty
    fi
    _reexec_tmp="$(mktemp "${TMPDIR:-/tmp}/rw-back-install.XXXXXX")"
    cat > "$_reexec_tmp"
    chmod 700 "$_reexec_tmp"
    bash "$_reexec_tmp" "$@" < /dev/tty
    _reexec_rc=$?
    rm -f "$_reexec_tmp"
    exit "$_reexec_rc"
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
RAW_MAIN="https://raw.githubusercontent.com/$REPO/main"
UPDATE_CACHE_TTL=21600
UPDATE_FAIL_CACHE_TTL=60
SETUP_CODE_MINUTES=30
SETUP_CODE_TTL=$((SETUP_CODE_MINUTES * 60))

print_message() {
    local type="$1" message="$2" color="$RESET"
    case "$type" in
        SUCCESS) color="$GREEN" ;;
        WARN) color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        ACTION) color="$CYAN" ;;
        INFO) color="$LIGHT_GRAY" ;;
    esac
    [[ "${_UI_SPIN_ON:-0}" == "1" ]] && ui_spin_stop
    echo -e "${color}[${type}]${RESET} ${message}"
}

die() {
    print_message "ERROR" "$*"
    exit 1
}

ui_interactive() {
    [[ -t 0 && -t 1 && "${TERM:-dumb}" != "dumb" && "${RW_PLAIN_UI:-0}" != "1" ]]
}

_UI_SPIN_PID=""
_UI_SPIN_ON=0

ui_spin_start() {
    local msg="$1"
    ui_spin_stop
    _UI_SPIN_ON=1
    if ! ui_interactive; then
        print_message "INFO" "$msg"
        return 0
    fi
    (
        local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0 started=$SECONDS
        while true; do
            printf '\r\e[2K%s%s%s %s %s· %d с%s' "$CYAN" "${frames[i]}" "$RESET" "$msg" "$LIGHT_GRAY" "$((SECONDS - started))" "$RESET"
            i=$(( (i + 1) % 10 ))
            sleep 0.1
        done
    ) &
    _UI_SPIN_PID=$!
    printf '\e[?25l'
}

ui_spin_stop() {
    if [[ -n "$_UI_SPIN_PID" ]]; then
        kill "$_UI_SPIN_PID" 2>/dev/null || true
        wait "$_UI_SPIN_PID" 2>/dev/null || true
        _UI_SPIN_PID=""
        printf '\r\e[2K\e[?25h'
    fi
    _UI_SPIN_ON=0
}

ui_restore() {
    ui_spin_stop
    if [[ -t 0 ]]; then
        stty echo 2>/dev/null || true
        printf '\e[?25h'
    fi
}

trap ui_restore EXIT

_ui_strip() {
    sed $'s/\x1b\\[[0-9;]*m//g' <<< "$1"
}

ui_status_card() {
    local LC_ALL=C.UTF-8
    local title="$1"
    shift
    local title_plain lw=0 vw=0 i j label plain inner cols hr="" pad
    title_plain=$(_ui_strip "$title")
    for ((i = 1; i <= $#; i += 2)); do
        j=$((i + 1))
        label="${!i}"
        plain=$(_ui_strip "${!j}")
        (( ${#label} > lw )) && lw=${#label}
        (( ${#plain} > vw )) && vw=${#plain}
    done
    inner=$((lw + 3 + vw))
    (( ${#title_plain} > inner )) && inner=${#title_plain}
    cols=$(tput cols 2>/dev/null || echo 80)
    if (( inner + 6 > cols )); then
        echo -e "  ${title}${RESET}"
        for ((i = 1; i <= $#; i += 2)); do
            j=$((i + 1))
            label="${!i}"
            echo -e "  ${LIGHT_GRAY}${label}${RESET}$(printf '%*s' $((lw - ${#label} + 3)) '')${!j}${RESET}"
        done
        return 0
    fi
    for ((i = 0; i < inner + 4; i++)); do hr+="─"; done
    echo -e "${GREEN}╭${hr}╮${RESET}"
    echo -e "${GREEN}│${RESET}  ${title}${RESET}$(printf '%*s' $((inner - ${#title_plain} + 2)) '')${GREEN}│${RESET}"
    if (( $# > 0 )); then
        echo -e "${GREEN}├${hr}┤${RESET}"
        for ((i = 1; i <= $#; i += 2)); do
            j=$((i + 1))
            label="${!i}"
            plain=$(_ui_strip "${!j}")
            pad=$((inner - lw - 3 - ${#plain} + 2))
            echo -e "${GREEN}│${RESET}  ${LIGHT_GRAY}${label}${RESET}$(printf '%*s' $((lw - ${#label} + 3)) '')${!j}${RESET}$(printf '%*s' "$pad" '')${GREEN}│${RESET}"
        done
    fi
    echo -e "${GREEN}╰${hr}╯${RESET}"
}

ui_box() {
    local title="$1" sub="${2:-}"
    echo ""
    ui_status_card "${GREEN}${BOLD}${title}${RESET}${sub:+  ${LIGHT_GRAY}${sub}${RESET}}"
    echo ""
}

ui_pause() {
    read -rp "$(echo -e "${LIGHT_GRAY}Нажмите Enter для продолжения...${RESET}")" || true
}

ui_yesno() {
    local a
    while true; do
        if ! read -rp "$(echo -e "${GREEN}[?]${RESET} ${1} (${GREEN}${BOLD}Y${RESET}/${RED}${BOLD}N${RESET}): ")" a; then
            echo ""
            return 1
        fi
        case "${a,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo -e "    ${YELLOW}Введите Y — да или N — нет.${RESET}" ;;
        esac
    done
}

ui_input() {
    local __var="$1" label="$2" hint="${3:-}" note="${4:-}" value=""
    label="${label%: }"; label="${label%:}"
    if ! ui_interactive; then
        if ! read -rp "${label}: " value; then
            printf -v "$__var" '%s' ""
            return 1
        fi
        printf -v "$__var" '%s' "$value"
        return 0
    fi
    echo -e "   ${BOLD}${label}${RESET}"
    [[ -n "$note" ]] && echo -e "   ${LIGHT_GRAY}${note}${RESET}"
    if ! read -re -i "$hint" -p "   $(echo -e "${GREEN}›${RESET}") " value; then
        printf -v "$__var" '%s' ""
        return 1
    fi
    printf -v "$__var" '%s' "$value"
}

ui_secret() {
    local __var="$1" label="$2" note="${3:-}" value=""
    label="${label%: }"; label="${label%:}"
    if ! ui_interactive; then
        if ! read -rsp "${label}: " value; then
            echo ""
            printf -v "$__var" '%s' ""
            return 1
        fi
        echo ""
    else
        echo -e "   ${BOLD}${label}${RESET}"
        [[ -n "$note" ]] && echo -e "   ${LIGHT_GRAY}${note}${RESET}"
        if ! read -rsp "   $(echo -e "${GREEN}›${RESET}") " value; then
            echo ""
            printf -v "$__var" '%s' ""
            return 1
        fi
        echo ""
    fi
    printf -v "$__var" '%s' "$value"
}

_UI_M_KEYS=()
_UI_M_LABELS=()
_UI_M_STYLES=()
_UI_M_FOOTER=()
_UI_M_DRAWN=0

menu_reset() {
    _UI_M_KEYS=()
    _UI_M_LABELS=()
    _UI_M_STYLES=()
    _UI_M_FOOTER=()
    _UI_M_DRAWN=0
}

menu_add() {
    _UI_M_KEYS+=("$1")
    _UI_M_LABELS+=("$2")
    _UI_M_STYLES+=("${3:-}")
}

menu_gap() {
    _UI_M_KEYS+=("")
    _UI_M_LABELS+=("")
    _UI_M_STYLES+=("gap")
}

menu_footer() {
    _UI_M_FOOTER+=("$1")
}

_ui_m_style() {
    case "$1" in
        primary) printf '%s' "${GREEN}${BOLD}" ;;
        warn) printf '%s' "$YELLOW" ;;
        danger) printf '%s' "$RED" ;;
        *) printf '%s' "" ;;
    esac
}

_ui_m_index_of() {
    local i
    for ((i = 0; i < ${#_UI_M_KEYS[@]}; i++)); do
        [[ "${_UI_M_STYLES[$i]}" != "gap" && "${_UI_M_KEYS[$i]}" == "$1" ]] && { echo "$i"; return 0; }
    done
    return 1
}

_ui_m_next() {
    local i="$1" dir="$2" n="${#_UI_M_KEYS[@]}" step
    for ((step = 0; step < n; step++)); do
        if (( i < 0 )); then
            i=0
        else
            i=$(( (i + dir + n) % n ))
        fi
        [[ "${_UI_M_STYLES[$i]}" != "gap" ]] && { echo "$i"; return 0; }
    done
    echo 0
}

_ui_m_has_prefix() {
    local k
    for k in "${_UI_M_KEYS[@]}"; do
        [[ -n "$k" && "$k" != "$1" && "$k" == "$1"* ]] && return 0
    done
    return 1
}

_ui_m_print() {
    local sel="$1" first="$2" last="$3" final="${4:-0}" total="${#_UI_M_KEYS[@]}" i st num lines=0 f hint hint_color
    if (( first > 0 )); then
        printf '\r\e[2K   %s↑ выше есть ещё пункты%s\n' "$LIGHT_GRAY" "$RESET"
        lines=$((lines + 1))
    elif (( last < total - 1 || _UI_M_WINDOWED )); then
        printf '\r\e[2K\n'
        lines=$((lines + 1))
    fi
    for ((i = first; i <= last; i++)); do
        if [[ "${_UI_M_STYLES[$i]}" == "gap" ]]; then
            printf '\r\e[2K\n'
            lines=$((lines + 1))
            continue
        fi
        st=$(_ui_m_style "${_UI_M_STYLES[$i]}")
        num=$(printf '%*s' "$_UI_M_KW" "${_UI_M_KEYS[$i]}")
        if (( i == sel )); then
            printf '\r\e[2K %s▸%s %s%s%s. %s %s\n' "${GREEN}${BOLD}" "$RESET" "$UI_SEL_BG" "$BOLD" "$num" "${_UI_M_LABELS[$i]}" "$RESET"
        else
            printf '\r\e[2K   %s%s. %s%s\n' "$st" "$num" "${_UI_M_LABELS[$i]}" "$RESET"
        fi
        lines=$((lines + 1))
    done
    if (( last < total - 1 )); then
        printf '\r\e[2K   %s↓ ниже есть ещё пункты%s\n' "$LIGHT_GRAY" "$RESET"
        lines=$((lines + 1))
    elif (( _UI_M_WINDOWED )); then
        printf '\r\e[2K\n'
        lines=$((lines + 1))
    fi
    if (( ! final )); then
        hint_color="$LIGHT_GRAY"
        if [[ -n "${_UI_M_WARN:-}" ]]; then
            hint="Пункта «${_UI_M_WARN}» нет — введите номер заново"
            hint_color="$YELLOW"
        elif [[ -n "${_UI_M_TYPED:-}" ]]; then
            hint="Номер: ${_UI_M_TYPED} · Enter — выбрать · Backspace — стереть"
            hint_color="$GREEN"
        else
            hint="↑/↓ или номер пункта · Enter — выбрать"
        fi
        printf '\r\e[2K\n\r\e[2K   %s%s%s\n' "$hint_color" "$hint" "$RESET"
        lines=$((lines + 2))
        for f in "${_UI_M_FOOTER[@]}"; do
            printf '\r\e[2K   %s%s%s\n' "$LIGHT_GRAY" "$f" "$RESET"
            lines=$((lines + 1))
        done
    fi
    _UI_M_DRAWN=$lines
}

menu_choose() {
    local __var="$1" init="${2:-}" n="${#_UI_M_KEYS[@]}" sel=0 i key rest rows max first last drawn=0
    _UI_M_TYPED=""
    _UI_M_WARN=""
    _UI_M_KW=1
    for i in "${_UI_M_KEYS[@]}"; do
        (( ${#i} > _UI_M_KW )) && _UI_M_KW=${#i}
    done
    if ! ui_interactive; then
        while true; do
            echo ""
            for ((i = 0; i < n; i++)); do
                if [[ "${_UI_M_STYLES[$i]}" == "gap" ]]; then
                    echo ""
                    continue
                fi
                echo -e " $(_ui_m_style "${_UI_M_STYLES[$i]}")$(printf '%*s' "$_UI_M_KW" "${_UI_M_KEYS[$i]}"). ${_UI_M_LABELS[$i]}${RESET}"
            done
            for i in "${_UI_M_FOOTER[@]}"; do
                echo -e "   ${LIGHT_GRAY}${i}${RESET}"
            done
            if ! read -rp "$(echo -e "${GREEN}[?]${RESET} Выберите пункт: ")" key; then
                echo ""
                exit 1
            fi
            if i=$(_ui_m_index_of "$key"); then
                printf -v "$__var" '%s' "${_UI_M_KEYS[$i]}"
                return 0
            fi
            print_message "ERROR" "Нет такого пункта"
        done
    fi
    if [[ -n "$init" ]] && i=$(_ui_m_index_of "$init"); then
        sel=$i
    elif [[ "${_UI_M_STYLES[0]:-}" == "gap" ]]; then
        sel=$(_ui_m_next 0 1)
    fi
    rows=$(tput lines 2>/dev/null || echo 24)
    max=$((rows - 10))
    (( max < 5 )) && max=5
    first=0
    last=$((n - 1))
    _UI_M_WINDOWED=0
    (( n > max )) && _UI_M_WINDOWED=1
    printf '\e[?25l'
    stty -echo 2>/dev/null || true
    while true; do
        if (( n > max && sel >= 0 )); then
            (( sel < first )) && first=$sel
            (( sel > first + max - 1 )) && first=$((sel - max + 1))
            last=$((first + max - 1))
            (( last > n - 1 )) && last=$((n - 1))
        fi
        (( drawn > 0 )) && printf '\e[%dA' "$drawn"
        _ui_m_print "$sel" "$first" "$last"
        drawn=$_UI_M_DRAWN
        if ! IFS= read -rsn1 key; then
            stty echo 2>/dev/null || true
            printf '\e[?25h'
            exit 1
        fi
        case "$key" in
            $'\e')
                rest=""
                IFS= read -rsn2 -t 0.05 rest || true
                case "$rest" in
                    '[A'|'OA') if (( sel < 0 )); then sel=$(_ui_m_next "$n" -1); else sel=$(_ui_m_next "$sel" -1); fi ;;
                    '[B'|'OB') if (( sel < 0 )); then sel=$(_ui_m_next -1 1); else sel=$(_ui_m_next "$sel" 1); fi ;;
                    '[H'|'OH') sel=$(_ui_m_next -1 1) ;;
                    '[F'|'OF') sel=$(_ui_m_next "$n" -1) ;;
                    '') if i=$(_ui_m_index_of "0"); then sel=$i; break; fi ;;
                    *) IFS= read -rsn5 -t 0.02 rest || true ;;
                esac
                _UI_M_TYPED=""
                _UI_M_WARN=""
                ;;
            k) if (( sel < 0 )); then sel=$(_ui_m_next "$n" -1); else sel=$(_ui_m_next "$sel" -1); fi; _UI_M_TYPED=""; _UI_M_WARN="" ;;
            j) if (( sel < 0 )); then sel=$(_ui_m_next -1 1); else sel=$(_ui_m_next "$sel" 1); fi; _UI_M_TYPED=""; _UI_M_WARN="" ;;
            '') (( sel >= 0 )) && break ;;
            $'\x7f'|$'\b')
                _UI_M_TYPED="${_UI_M_TYPED%?}"
                _UI_M_WARN=""
                if [[ -n "$_UI_M_TYPED" ]] && i=$(_ui_m_index_of "$_UI_M_TYPED"); then sel=$i; fi
                ;;
            *)
                _UI_M_WARN=""
                local cand="${_UI_M_TYPED}${key}"
                if i=$(_ui_m_index_of "$cand"); then
                    _UI_M_TYPED="$cand"
                    sel=$i
                elif _ui_m_has_prefix "$cand"; then
                    _UI_M_TYPED="$cand"
                else
                    _UI_M_WARN="$cand"
                    _UI_M_TYPED=""
                    sel=-1
                fi
                ;;
        esac
    done
    printf '\e[%dA' "$drawn"
    _ui_m_print "$sel" "$first" "$last" 1
    printf '\e[J'
    stty echo 2>/dev/null || true
    printf '\e[?25h'
    printf -v "$__var" '%s' "${_UI_M_KEYS[$sel]}"
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        die "Нужны права root: sudo bash $0"
    fi
}

load_config() {
    BOT_TOKEN=""; CHAT_ID=""; BOT_ADMIN_IDS=""
    DB_USER="postgres"; DB_NAME="postgres"; DB_CONTAINER="remnawave-db"
    PANEL_CONTAINER="remnawave"; CACHE_CONTAINER="remnawave-redis"
    CRON_HOURS="0"; KEEP_FILES="5"; KEEP_DAYS="0"; KEEP_MODE="files"; PANEL_DIR="/opt/remnawave"

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
    KEEP_DAYS=${KEEP_DAYS:-0}
    KEEP_MODE=${KEEP_MODE:-files}
    BOT_ADMIN_IDS=${BOT_ADMIN_IDS:-}
    [[ "$CRON_HOURS" =~ ^[0-9]+$ ]] || CRON_HOURS=0
    [[ "$KEEP_FILES" =~ ^[0-9]+$ ]] || KEEP_FILES=5
    [[ "$KEEP_DAYS" =~ ^[0-9]+$ ]] || KEEP_DAYS=0
    [[ "$KEEP_MODE" == "days" ]] || KEEP_MODE="files"
    CRON_HOURS=$((10#$CRON_HOURS))
    KEEP_FILES=$((10#$KEEP_FILES))
    KEEP_DAYS=$((10#$KEEP_DAYS))
    if [[ "$KEEP_MODE" == "days" ]] && (( KEEP_DAYS < 1 )); then
        KEEP_MODE="files"
    fi
    ui_colors_init
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
        printf 'KEEP_DAYS=%q\n' "$KEEP_DAYS"
        printf 'KEEP_MODE=%q\n' "$KEEP_MODE"
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

install_deps() {
    local need=(curl jq gzip cron)
    local missing=() p
    for p in "${need[@]}"; do
        command -v "$p" > /dev/null 2>&1 || missing+=("$p")
    done
    if ! command -v crontab > /dev/null 2>&1; then
        missing+=("cron")
    fi
    if ! command -v flock > /dev/null 2>&1; then
        missing+=("util-linux")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        ui_spin_start "Устанавливаю пакеты: ${missing[*]}"
        if command -v apt-get > /dev/null 2>&1; then
            apt-get update -qq > /dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" > /dev/null 2>&1 || true
        elif command -v dnf > /dev/null 2>&1; then
            dnf install -y "${missing[@]}" > /dev/null 2>&1 || true
        elif command -v yum > /dev/null 2>&1; then
            yum install -y "${missing[@]}" > /dev/null 2>&1 || true
        fi
        ui_spin_stop
    fi

    for p in curl jq gzip flock; do
        command -v "$p" > /dev/null 2>&1 || die "Не установлен $p"
    done
    command -v crontab > /dev/null 2>&1 || print_message "WARN" "cron не установлен: ручные бэкапы доступны, расписание — нет"
}

fetch_file() {
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
    mv -f "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
    return 0
}

install_self() {
    print_message "INFO" "Раскладываю файлы в ${BOLD}${INSTALL_DIR}${RESET}…"
    mkdir -p "$INSTALL_DIR" "$BACKUP_DIR" "$STATE_DIR" "$LOG_DIR" "$INSTALL_DIR/scripts"

    if [[ "$SELF_IS_SCRIPT" == true && "$SELF_PATH" != "$INSTALL_DIR/install.sh" ]]; then
        cp -f "$SELF_PATH" "$INSTALL_DIR/install.sh" || die "Не удалось скопировать установщик"
    elif [[ ! -s "$INSTALL_DIR/install.sh" ]]; then
        print_message "INFO" "Скачиваю install.sh из GitHub…"
        fetch_file "$RAW_MAIN/install.sh" "$INSTALL_DIR/install.sh" "rw-back" ||
            die "Не удалось скачать install.sh"
    fi
    chmod 755 "$INSTALL_DIR/install.sh"

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
        if ln -sfn "$INSTALL_DIR/install.sh" "$SYMLINK_PATH" 2>/dev/null; then
            print_message "SUCCESS" "Команда ${BOLD}rw-back${RESET} доступна"
        else
            print_message "WARN" "Не удалось создать ссылку $SYMLINK_PATH"
        fi
    fi
}

generate_setup_code() {
    local raw
    raw=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')
    [[ "$raw" =~ ^[0-9]+$ ]] || raw=$((RANDOM * 32768 + RANDOM))
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

wait_admin_binding() {
    local timeout="${1:-1800}" waited=0 id
    while (( waited < timeout )); do
        id="$(main_admin_id)"
        [[ "$id" =~ ^[0-9]+$ ]] && return 0
        if ! bot_service_active; then
            print_message "ERROR" "Служба остановилась во время ожидания привязки"
            return 1
        fi
        sleep 3
        waited=$((waited + 3))
    done
    return 1
}

setup_admin_flow() {
    local existing username code id choice
    [[ -n "$BOT_TOKEN" ]] || {
        print_message "INFO" "Telegram пропущен. Привязка админа не требуется."
        return 0
    }
    existing="$(main_admin_id)"
    if [[ "$existing" =~ ^[0-9]+$ ]]; then
        print_message "SUCCESS" "Главный админ уже привязан: ${BOLD}${existing}${RESET}"
        return 0
    fi

    username="$(bot_username_of)"
    if [[ -z "$username" ]]; then
        print_message "ERROR" "Не удалось проверить токен: он неверен или Telegram недоступен"
        return 1
    fi

    code="$(generate_setup_code)"
    write_setup_code "$code" || { print_message "ERROR" "Не удалось сохранить код"; return 1; }

    echo ""
    ui_status_card "${GREEN}${BOLD}ПРИВЯЗКА ГЛАВНОГО АДМИНА${RESET}" \
        "Код" "${GREEN}${BOLD}${code}${RESET}" \
        "Бот" "${BOLD}@${username}${RESET}" \
        "Действует" "${BOLD}${SETUP_CODE_MINUTES} минут${RESET}"
    echo ""
    echo -e "   1. Откройте ${BOLD}https://t.me/${username}${RESET}"
    echo -e "   2. Напишите ${BOLD}/start${RESET}"
    echo -e "   3. Отправьте код ${BOLD}${GREEN}${code}${RESET}"
    echo ""
    menu_reset
    menu_add 1 "Ожидать привязку" primary
    menu_add 0 "Продолжить — привязать позже"
    menu_choose choice
    if [[ "$choice" == "0" ]]; then
        print_message "INFO" "Код сохранён. Завершить позже: rw-back admin-code"
        return 0
    fi

    print_message "INFO" "Жду привязку до ${SETUP_CODE_MINUTES} минут…"
    if wait_admin_binding "$SETUP_CODE_TTL"; then
        load_config
        id="$(main_admin_id)"
        print_message "SUCCESS" "Главный админ привязан: ${BOLD}${id}${RESET}"
        return 0
    fi

    print_message "WARN" "Привязка не произошла. Можно продолжить позже без переустановки."
    print_message "INFO" "Новый код: ${BOLD}rw-back admin-code${RESET}"
    return 1
}

cmd_admin_code() {
    load_config
    mkdir -p "$STATE_DIR"
    local existing username code
    existing="$(main_admin_id)"
    if [[ "$existing" =~ ^[0-9]+$ ]]; then
        print_message "INFO" "Главный админ уже привязан: ${existing}"
        print_message "INFO" "Добавить других: бот → Настройки → Админы"
        return 0
    fi
    if [[ -z "$BOT_TOKEN" ]]; then
        print_message "WARN" "Telegram ещё не настроен"
        if ui_interactive; then
            menu_telegram_settings
            [[ -n "$BOT_TOKEN" ]] || return 1
            cmd_admin_code
            return $?
        fi
        print_message "INFO" "Сначала задайте токен: rw-back → Настройки → Telegram"
        return 1
    fi
    username="$(bot_username_of)"
    if [[ -z "$username" ]]; then
        print_message "ERROR" "Не удалось проверить токен: он неверен или Telegram недоступен"
        return 1
    fi
    if ! bot_service_active; then
        print_message "WARN" "Служба не запущена — бот пока не сможет принять код"
        if ! ui_yesno "Запустить службу сейчас?"; then
            print_message "INFO" "Сначала запустите: rw-back bot-install"
            return 1
        fi
        install_bot_service || return 1
    fi
    code="$(generate_setup_code)"
    write_setup_code "$code" || die "Не удалось сохранить код"

    echo ""
    ui_status_card "${GREEN}${BOLD}КОД ПРИВЯЗКИ АДМИНА${RESET}" \
        "Код" "${GREEN}${BOLD}${code}${RESET}" \
        "Действует" "${BOLD}${SETUP_CODE_MINUTES} минут${RESET}"
    echo "  1. Откройте https://t.me/${username}"
    echo "  2. Отправьте /start"
    echo "  3. Отправьте код: ${code}"
    echo ""
    return 0
}

mask_token() {
    local token="${1:-}"
    if [[ -z "$token" ]]; then
        printf 'не задан'
    elif (( ${#token} > 12 )); then
        printf '%s…%s' "${token:0:6}" "${token: -4}"
    else
        printf '••••••••'
    fi
}

configure_telegram() {
    local old_token="$BOT_TOKEN" new_token bot_user choice existing
    while true; do
        if ! ui_secret new_token "API Token" "Получить: @BotFather → /newbot. Пустой ввод — отмена."; then
            BOT_TOKEN="$old_token"
            print_message "WARN" "Ввод завершён. Настройки Telegram не изменены."
            return 1
        fi
        new_token="${new_token//[[:space:]]/}"
        if [[ -z "$new_token" ]]; then
            BOT_TOKEN="$old_token"
            print_message "INFO" "Настройку Telegram отменили, прежние параметры сохранены"
            return 1
        fi
        BOT_TOKEN="$new_token"
        ui_spin_start "Проверяю токен в Telegram"
        bot_user="$(bot_username_of)"
        ui_spin_stop
        if [[ -n "$bot_user" ]]; then
            print_message "SUCCESS" "Бот подключён: ${BOLD}@${bot_user}${RESET}"
            if [[ -z "$CHAT_ID" ]]; then
                existing="$(main_admin_id)"
                [[ "$existing" =~ ^[0-9]+$ ]] && CHAT_ID="$existing"
            fi
            save_config || { BOT_TOKEN="$old_token"; print_message "ERROR" "Не удалось сохранить конфигурацию"; return 1; }
            if [[ "$old_token" != "$new_token" ]]; then
                rm -f "$STATE_DIR/setup_code" "$STATE_DIR/setup_attempts" 2>/dev/null
            fi
            return 0
        fi
        BOT_TOKEN="$old_token"
        print_message "ERROR" "Токен не проверен: он неверен или Telegram недоступен"
        menu_reset
        menu_add 1 "Ввести другой токен" primary
        menu_add 0 "Отменить настройку"
        menu_choose choice
        [[ "$choice" == "0" ]] && return 1
    done
}

finish_telegram_setup() {
    if [[ -z "$BOT_TOKEN" ]]; then
        print_message "SUCCESS" "Локальный режим готов: бэкап и восстановление доступны без Telegram"
        print_message "INFO" "Бот позже: rw-back → Telegram-бот → Настроить"
        return 0
    fi
    if ! install_bot_service; then
        print_message "WARN" "Файлы и настройки сохранены, но Telegram-служба не запущена"
        return 1
    fi
    setup_admin_flow || true
    load_config
    if ! bot_service_active; then
        print_message "WARN" "Telegram-служба остановилась. Проверьте логи и перезапустите её из меню."
        return 1
    fi
    return 0
}

setup_telegram_now() {
    if ! configure_telegram; then
        print_message "INFO" "Локальные бэкапы продолжают работать без Telegram"
        return 1
    fi
    finish_telegram_setup
}

wizard_telegram() {
    print_message "ACTION" "1. Telegram — необязательный шаг"
    echo -e "   ${LIGHT_GRAY}Локальные бэкапы работают и без бота. Настроить можно позже в меню.${RESET}"
    echo ""
    local choice
    if [[ -n "$BOT_TOKEN" ]]; then
        print_message "INFO" "Текущий токен: $(mask_token "$BOT_TOKEN")"
        menu_reset
        menu_add 1 "Оставить текущие настройки" primary
        menu_add 2 "Изменить токен"
        menu_add 3 "Отключить Telegram" danger
        menu_choose choice
        case "$choice" in
            2) configure_telegram || true ;;
            3)
                if bot_service_installed; then
                    remove_bot_service || { print_message "ERROR" "Telegram не отключён: службу удалить не удалось"; return 1; }
                fi
                BOT_TOKEN=""
                save_config || die "Не удалось сохранить конфигурацию"
                print_message "WARN" "Telegram отключён. Локальные бэкапы доступны."
                ;;
        esac
    else
        configure_telegram || print_message "WARN" "Telegram пропущен. Позже: rw-back → Telegram-бот"
    fi
    echo ""
}

wizard() {
    clear 2>/dev/null || true
    ui_box "RW-BACK · ПЕРВИЧНАЯ НАСТРОЙКА"

    wizard_telegram || return 1

    local choice input custom
    print_message "ACTION" "2. База данных"
    ui_input input "Контейнер БД" "$DB_CONTAINER"
    DB_CONTAINER="${input:-$DB_CONTAINER}"
    ui_input input "Пользователь БД" "$DB_USER"
    DB_USER="${input:-$DB_USER}"
    ui_input input "Имя базы" "$DB_NAME"
    DB_NAME="${input:-$DB_NAME}"
    echo ""

    print_message "ACTION" "3. Панель Remnawave"
    menu_reset
    menu_add 1 "Оставить: $PANEL_DIR"
    menu_add 2 "/opt/remnawave"
    menu_add 3 "/root/remnawave"
    menu_add 4 "/opt/stacks/remnawave"
    menu_add 5 "Свой путь"
    menu_choose choice
    case "$choice" in
        2) PANEL_DIR="/opt/remnawave" ;;
        3) PANEL_DIR="/root/remnawave" ;;
        4) PANEL_DIR="/opt/stacks/remnawave" ;;
        5)
            while true; do
                ui_input custom "Полный путь к панели" "$PANEL_DIR" || { print_message "ERROR" "Ввод завершён"; return 1; }
                if [[ -n "$custom" && "$custom" = /* && "$custom" != "/" ]]; then
                    PANEL_DIR="${custom%/}"
                    break
                fi
                print_message "ERROR" "Нужен абсолютный путь, отличный от /"
            done
            ;;
    esac
    echo ""

    print_message "ACTION" "4. Хранение архивов"
    menu_reset
    menu_add 1 "По файлам — оставлять последние N"
    menu_add 2 "По дням — удалять старше N дней"
    menu_choose keep_pick
    case "$keep_pick" in
        2)
            KEEP_MODE="days"
            while true; do
                ui_input input "Сколько дней хранить (1–365)" "${KEEP_DAYS:-7}" || { print_message "ERROR" "Ввод завершён"; return 1; }
                input="${input:-7}"
                if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= 365 )); then
                    KEEP_DAYS="$input"
                    break
                fi
                print_message "ERROR" "Введите число от 1 до 365"
            done
            ;;
        *)
            KEEP_MODE="files"
            while true; do
                ui_input input "Сколько файлов хранить (1–200)" "$KEEP_FILES" || { print_message "ERROR" "Ввод завершён"; return 1; }
                input="${input:-$KEEP_FILES}"
                if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= 200 )); then
                    KEEP_FILES="$input"
                    break
                fi
                print_message "ERROR" "Введите число от 1 до 200"
            done
            ;;
    esac

    save_config || die "Не удалось сохранить конфигурацию"
    print_message "SUCCESS" "Настройки сохранены"
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

remote_version() {
    local force="${1:-}" cache="$STATE_DIR/update_cache" ts ver
    mkdir -p "$STATE_DIR" 2>/dev/null
    if [[ "$force" != "force" && -f "$cache" ]]; then
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

    ver=$(curl -s --max-time 10 -H "User-Agent: rw-back" "$RAW_MAIN/VERSION" 2>/dev/null | head -n 1 | tr -d '[:space:]')
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

bot_service_active() {
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

bot_service_installed() {
    [[ -f "$SERVICE_FILE" ]]
}

install_bot_service() {
    require_root
    if [[ -z "$BOT_TOKEN" ]]; then
        print_message "WARN" "Служба не запущена: Telegram ещё не настроен"
        if ui_interactive; then
            menu_telegram_settings
            [[ -n "$BOT_TOKEN" ]] && bot_service_active && return 0
            return 1
        fi
        print_message "INFO" "Настроить: rw-back → Настройки → Telegram"
        return 1
    fi
    if ! command -v systemctl > /dev/null 2>&1; then
        print_message "ERROR" "systemd не найден. Бот можно запустить вручную: $BOT_SCRIPT serve"
        return 1
    fi

    mkdir -p "$STATE_DIR" "$BACKUP_DIR" "$LOG_DIR" || {
        print_message "ERROR" "Не удалось создать рабочие каталоги"
        return 1
    }

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=rw-back Telegram bot (Remnawave DB import/export)
After=network-online.target docker.service
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/bin/bash $BOT_SCRIPT serve
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=rw-back-bot

[Install]
WantedBy=multi-user.target
EOF

    if [[ ! -s "$SERVICE_FILE" ]] || ! chmod 644 "$SERVICE_FILE"; then
        print_message "ERROR" "Не удалось записать $SERVICE_FILE"
        return 1
    fi
    systemctl daemon-reload > /dev/null 2>&1 || { print_message "ERROR" "systemctl daemon-reload завершился ошибкой"; return 1; }
    systemctl enable "$SERVICE_NAME" > /dev/null 2>&1 || print_message "WARN" "Служба создана, но автозапуск включить не удалось"

    ui_spin_start "Запускаю Telegram-службу"
    if systemctl restart "$SERVICE_NAME" 2>/dev/null; then
        sleep 2
    fi
    ui_spin_stop
    if bot_service_active; then
        print_message "SUCCESS" "Служба ${SERVICE_NAME} запущена"
        if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
            print_message "INFO" "Автозапуск включён · логи: journalctl -u ${SERVICE_NAME} -f"
        else
            print_message "WARN" "Служба работает, но автозапуск не включён"
        fi
        return 0
    fi
    print_message "ERROR" "Служба не поднялась. Смотрите: journalctl -u ${SERVICE_NAME} -n 50"
    return 1
}

remove_bot_service() {
    require_root
    local failed=0
    if command -v systemctl > /dev/null 2>&1; then
        if bot_service_active && ! systemctl stop "$SERVICE_NAME" > /dev/null 2>&1; then
            print_message "ERROR" "Не удалось остановить службу"
            failed=1
        fi
        if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null && ! systemctl disable "$SERVICE_NAME" > /dev/null 2>&1; then
            print_message "ERROR" "Не удалось отключить автозапуск"
            failed=1
        fi
    elif [[ -e "$SERVICE_FILE" ]]; then
        print_message "ERROR" "systemd не найден, удалите $SERVICE_FILE вручную"
        return 1
    fi
    if [[ -e "$SERVICE_FILE" ]] && ! rm -f "$SERVICE_FILE"; then
        print_message "ERROR" "Не удалось удалить $SERVICE_FILE"
        failed=1
    fi
    if command -v systemctl > /dev/null 2>&1; then
        systemctl daemon-reload > /dev/null 2>&1 || failed=1
    fi
    (( failed == 0 )) || { print_message "ERROR" "Служба удалена не полностью"; return 1; }
    print_message "SUCCESS" "Служба удалена"
}

migrate_bot_service() {
    bot_service_installed || return 0
    grep -q '^Restart=always$' "$SERVICE_FILE" 2>/dev/null || return 0
    print_message "INFO" "Обновляю политику перезапуска Telegram-службы"
    if [[ -z "$BOT_TOKEN" ]]; then
        remove_bot_service
    else
        install_bot_service
    fi
}

cron_remove() {
    command -v crontab > /dev/null 2>&1 || return 0
    local tmp rc listing
    listing=$(crontab -l 2>&1)
    rc=$?
    if (( rc != 0 )); then
        if grep -qi 'no crontab for' <<< "$listing"; then
            listing=""
        else
            print_message "ERROR" "Не удалось прочитать crontab — чужие задачи не изменены"
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
    crontab "$tmp" 2>/dev/null
    rc=$?
    rm -f "$tmp"
    return "$rc"
}

do_update() {
    local auto="${1:-}"
    require_root
    load_config

    local current remote
    current="$(local_version)"
    remote="$(remote_version force)"

    if [[ -z "$remote" ]]; then
        print_message "ERROR" "Не удалось узнать версию с GitHub (нет сети?)"
        return 1
    fi
    print_message "INFO" "Текущая версия: ${current} · доступна: ${remote}"
    if ! version_compare "$current" "$remote"; then
        print_message "SUCCESS" "Уже последняя версия: ${current}"
        return 0
    fi

    print_message "ACTION" "Обновление ${current} → ${remote}"
    if [[ "$auto" != "--auto" ]]; then
        if ! ui_yesno "Продолжить обновление?"; then
            print_message "WARN" "Отменено"
            return 0
        fi
    fi

    local work
    work="$(mktemp -d)" || die "Нет места для загрузки"

    ui_spin_start "Загружаю новые файлы"
    if ! curl -fsSL --max-time 60 -H "User-Agent: rw-back" -o "$work/rw-back-bot.sh" "$RAW_MAIN/rw-back-bot.sh"; then
        rm -rf "$work"; die "Не удалось скачать rw-back-bot.sh"
    fi
    if ! curl -fsSL --max-time 60 -H "User-Agent: rw-back" -o "$work/install.sh" "$RAW_MAIN/install.sh"; then
        rm -rf "$work"; die "Не удалось скачать install.sh"
    fi
    if ! curl -fsSL --max-time 60 -H "User-Agent: rw-back" -o "$work/VERSION" "$RAW_MAIN/VERSION" 2>/dev/null; then
        rm -rf "$work"; die "Не удалось скачать VERSION — обновление отменено"
    fi
    ui_spin_stop
    local downloaded_version
    downloaded_version="$(head -n 1 "$work/VERSION" | tr -d '[:space:]')"
    if [[ "${downloaded_version#v}" != "${remote#v}" ]]; then
        rm -rf "$work"; die "VERSION не совпадает с релизом — обновление отменено"
    fi

    if ! bash -n "$work/rw-back-bot.sh" 2>/dev/null; then
        rm -rf "$work"; die "Новый rw-back-bot.sh не прошёл проверку синтаксиса — обновление отменено"
    fi
    if ! bash -n "$work/install.sh" 2>/dev/null; then
        rm -rf "$work"; die "Новый install.sh не прошёл проверку синтаксиса — обновление отменено"
    fi
    grep -q 'rw-back-bot' "$work/rw-back-bot.sh" || { rm -rf "$work"; die "Файл бота повреждён"; }

    local stamp
    stamp="$(date +%Y%m%d_%H%M%S)"
    cp -f "$BOT_SCRIPT" "$INSTALL_DIR/scripts/rw-back-bot.sh.${stamp}.bak" 2>/dev/null || true
    cp -f "$INSTALL_DIR/install.sh" "$INSTALL_DIR/scripts/install.sh.${stamp}.bak" 2>/dev/null || true

    install -m 750 "$work/rw-back-bot.sh" "$BOT_SCRIPT" || die "Не удалось заменить бота"
    install -m 755 "$work/install.sh" "$INSTALL_DIR/install.sh" || die "Не удалось заменить установщик"
    if [[ -s "$work/VERSION" ]]; then
        install -m 644 "$work/VERSION" "$VERSION_FILE" || die "Не удалось обновить VERSION"
    fi
    rm -rf "$work"

    setup_symlink

    if bot_service_installed; then
        if [[ -z "$BOT_TOKEN" ]]; then
            remove_bot_service || { print_message "ERROR" "Файлы обновлены, но старую службу остановить не удалось"; return 1; }
            print_message "SUCCESS" "Обновлено до ${remote}. Telegram отключён, цикл перезапусков остановлен."
        else
            if install_bot_service; then
                print_message "SUCCESS" "Обновлено до ${remote}, бот перезапущен"
            else
                print_message "ERROR" "Файлы обновлены, но служба не поднялась. Проверьте: journalctl -u ${SERVICE_NAME} -n 50"
                return 1
            fi
        fi
    else
        print_message "SUCCESS" "Обновлено до ${remote}"
    fi
    return 0
}

do_remove() {
    require_root
    echo ""
    print_message "WARN" "Будут удалены:"
    echo "  • служба бота и cron-задача"
    echo "  • команда rw-back"
    echo "  • каталог $INSTALL_DIR (конфиг, состояние, логи)"
    echo ""
    if ui_yesno "Сохранить архивы бэкапов?"; then
        local stash
        stash="/root/rw-back-backups-$(date +%Y%m%d_%H%M%S)"
        if [[ -d "$BACKUP_DIR" ]]; then
            if mkdir -p "$stash" 2>/dev/null && cp -a "$BACKUP_DIR"/. "$stash"/ 2>/dev/null; then
                print_message "SUCCESS" "Архивы сохранены: $stash"
            else
                print_message "ERROR" "Не удалось сохранить архивы. Удаление отменено."
                return 1
            fi
        fi
    fi
    if ! ui_yesno "Точно удалить rw-back?"; then
        print_message "INFO" "Удаление отменено"
        return 0
    fi

    remove_bot_service || return 1
    cron_remove || { print_message "ERROR" "Не удалось удалить cron-задачу. Удаление отменено."; return 1; }
    rm -f "$SYMLINK_PATH" || { print_message "ERROR" "Не удалось удалить $SYMLINK_PATH"; return 1; }
    rm -rf "$INSTALL_DIR" || { print_message "ERROR" "Не удалось удалить $INSTALL_DIR"; return 1; }
    print_message "SUCCESS" "rw-back удалён"
    exit 0
}

pick_backup_file() {
    local files=() manual
    PICKED_BACKUP_FILE=""
    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'rw_db_backup_*.sql.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | cut -d' ' -f2-)

    if [[ ${#files[@]} -eq 0 ]]; then
        print_message "WARN" "В $BACKUP_DIR нет архивов"
        ui_input manual "Путь к файлу дампа" || { print_message "ERROR" "Ввод завершён"; return 1; }
        [[ -f "$manual" ]] || { print_message "ERROR" "Файл не найден"; return 1; }
        PICKED_BACKUP_FILE="$manual"
        return 0
    fi

    menu_reset
    local i=1 f
    for f in "${files[@]}"; do
        menu_add "$i" "${f##*/} ${LIGHT_GRAY}· $(du -h "$f" | awk '{print $1}')${RESET}"
        i=$((i + 1))
    done
    menu_gap
    menu_add 0 "Указать путь вручную"
    menu_footer "Архивы в ${BACKUP_DIR}"

    local choice
    menu_choose choice
    echo ""
    if [[ "$choice" == "0" ]]; then
        while true; do
            ui_input manual "Путь к файлу дампа" || { print_message "ERROR" "Ввод завершён"; return 1; }
            [[ -f "$manual" ]] && { PICKED_BACKUP_FILE="$manual"; return 0; }
            print_message "ERROR" "Файл не найден"
        done
    fi
    PICKED_BACKUP_FILE="${files[$((choice - 1))]}"
    return 0
}

menu_backup() {
    load_config
    bash "$BOT_SCRIPT" backup
    echo ""
    ui_pause
}

menu_restore() {
    load_config
    pick_backup_file || { ui_pause; return; }
    local file="$PICKED_BACKUP_FILE"
    echo ""
    print_message "WARN" "Текущая база будет перезаписана"
    if ! ui_yesno "Продолжить?"; then
        print_message "INFO" "Отменено"
        ui_pause
        return
    fi

    bash "$BOT_SCRIPT" restore "$file"
    echo ""
    ui_pause
}

menu_list() {
    load_config
    bash "$BOT_SCRIPT" list
    echo ""
    ui_pause
}

send_test_message() {
    local target="$CHAT_ID" resp
    if [[ -z "$BOT_TOKEN" ]]; then
        print_message "WARN" "Telegram не настроен. Сначала укажите токен."
        return 1
    fi
    [[ -n "$target" ]] || target="$(main_admin_id)"
    if [[ ! "$target" =~ ^-?[0-9]+$ ]]; then
        print_message "WARN" "Некуда отправить: привяжите админа или задайте чат уведомлений"
        return 1
    fi
    ui_spin_start "Отправляю тестовое сообщение"
    resp=$(curl -s --max-time 20 "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=$target" \
        --data-urlencode "text=🤖 rw-back: связь установлена" -d "parse_mode=HTML")
    ui_spin_stop
    if printf '%s' "$resp" | jq -e '.ok == true' > /dev/null 2>&1; then
        CHAT_ID="$target"
        save_config || print_message "WARN" "Сообщение отправлено, но чат не сохранён"
        print_message "SUCCESS" "Сообщение отправлено — проверьте чат"
        return 0
    fi
    print_message "ERROR" "Telegram: $(printf '%s' "$resp" | jq -r '.description // "нет ответа"')"
    return 1
}

menu_telegram_settings() {
    while true; do
        load_config
        clear 2>/dev/null || true
        local service_state="${YELLOW}не установлена${RESET}"
        if bot_service_installed; then
            bot_service_active && service_state="${GREEN}работает${RESET}" || service_state="${RED}остановлена${RESET}"
        fi
        ui_status_card "${GREEN}${BOLD}RW-BACK · TELEGRAM${RESET}" \
            "Токен" "${BOLD}$(mask_token "$BOT_TOKEN")${RESET}" \
            "Чат" "${BOLD}${CHAT_ID:-не задан}${RESET}" \
            "Админы" "${BOLD}${BOT_ADMIN_IDS:-не заданы}${RESET}" \
            "Служба" "$service_state"
        echo ""
        menu_reset
        menu_add 1 "Настроить / изменить токен и запустить" primary
        menu_add 2 "Чат уведомлений"
        [[ -n "$BOT_TOKEN" ]] && menu_add 3 "Код привязки главного админа"
        if [[ -n "$BOT_TOKEN" || -e "$SERVICE_FILE" ]]; then
            menu_add 4 "Отключить Telegram" danger
        fi
        menu_gap
        menu_add 0 "Назад"
        local choice input
        menu_choose choice
        echo ""
        case "$choice" in
            1) setup_telegram_now || true ;;
            2)
                ui_input input "ID чата уведомлений" "$CHAT_ID" "Enter — оставить текущий; для группы ID обычно отрицательный" || continue
                if [[ -n "$input" ]]; then
                    if [[ "$input" =~ ^-?[0-9]{1,20}$ ]]; then
                        CHAT_ID="$input"
                        save_config && print_message "SUCCESS" "Чат сохранён" || print_message "ERROR" "Не удалось сохранить конфигурацию"
                    else
                        print_message "ERROR" "Нужен числовой ID чата"
                    fi
                fi
                ;;
            3) cmd_admin_code || true ;;
            4)
                if ui_yesno "Отключить Telegram и остановить службу?"; then
                    if bot_service_installed; then
                        remove_bot_service || continue
                    fi
                    BOT_TOKEN=""
                    save_config && print_message "SUCCESS" "Telegram отключён. Локальные бэкапы доступны." || print_message "ERROR" "Не удалось сохранить конфигурацию"
                fi
                ;;
            0) return ;;
        esac
        echo ""
        ui_pause
    done
}

menu_bot() {
    while true; do
        load_config
        clear 2>/dev/null || true
        local service_state="${YELLOW}не установлена${RESET}"
        if bot_service_installed; then
            bot_service_active && service_state="${GREEN}работает${RESET}" || service_state="${RED}остановлена${RESET}"
        fi
        ui_status_card "${GREEN}${BOLD}RW-BACK · TELEGRAM-БОТ${RESET}" \
            "Токен" "${BOLD}$(mask_token "$BOT_TOKEN")${RESET}" \
            "Служба" "$service_state" \
            "Админы" "${BOLD}${BOT_ADMIN_IDS:-не заданы}${RESET}"
        echo ""
        menu_reset
        if [[ -z "$BOT_TOKEN" ]]; then
            menu_add 1 "Настроить Telegram и запустить" primary
        else
            menu_add 1 "Установить / перезапустить службу" primary
        fi
        if bot_service_installed; then
            menu_add 2 "Остановить и удалить службу"
            menu_add 3 "Логи"
        fi
        if [[ -n "$BOT_TOKEN" ]]; then
            menu_add 4 "Запустить в консоли (Ctrl+C — стоп)"
            menu_add 5 "Тестовое сообщение"
        fi
        menu_add 6 "Настройки Telegram"
        menu_gap
        menu_add 0 "Назад"
        local choice
        menu_choose choice
        echo ""
        case "$choice" in
            1)
                if [[ -z "$BOT_TOKEN" ]]; then setup_telegram_now || true; else install_bot_service || true; fi
                ;;
            2) remove_bot_service || true ;;
            3) journalctl -u "$SERVICE_NAME" -n 40 --no-pager 2>/dev/null || print_message "INFO" "Логов нет" ;;
            4) bash "$BOT_SCRIPT" serve ;;
            5) send_test_message || true ;;
            6) menu_telegram_settings; continue ;;
            0) return ;;
        esac
        echo ""
        ui_pause
    done
}

menu_settings() {
    while true; do
        load_config
        clear 2>/dev/null || true
        ui_box "RW-BACK · НАСТРОЙКИ"
        menu_reset
        menu_add 1 "Telegram: токен, чат и привязка" primary
        menu_add 2 "Контейнер и имя базы"
        menu_add 3 "Каталог панели"
        menu_add 4 "Админы бота"
        menu_add 5 "Хранение: по файлам или по дням"
        menu_gap
        menu_add 0 "Назад"
        local choice input
        menu_choose choice
        echo ""
        case "$choice" in
            1) menu_telegram_settings; continue ;;
            2)
                ui_input input "Контейнер БД" "$DB_CONTAINER" || return 1
                [[ -n "$input" ]] && DB_CONTAINER="$input"
                ui_input input "Пользователь БД" "$DB_USER" || return 1
                [[ -n "$input" ]] && DB_USER="$input"
                ui_input input "Имя базы" "$DB_NAME" || return 1
                [[ -n "$input" ]] && DB_NAME="$input"
                save_config && print_message "SUCCESS" "Настройки базы сохранены" || print_message "ERROR" "Не удалось сохранить конфигурацию"
                ;;
            3)
                ui_input input "Каталог панели" "$PANEL_DIR" || return 1
                if [[ -n "$input" ]]; then
                    if [[ "$input" = /* && "$input" != "/" ]]; then
                        PANEL_DIR="${input%/}"
                        save_config && print_message "SUCCESS" "Каталог сохранён" || print_message "ERROR" "Не удалось сохранить конфигурацию"
                    else
                        print_message "ERROR" "Нужен абсолютный путь, отличный от /"
                    fi
                fi
                ;;
            4)
                ui_input input "ID админов через запятую" "$BOT_ADMIN_IDS" || return 1
                if [[ -n "$input" ]]; then
                    if [[ "$input" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
                        BOT_ADMIN_IDS="$input"
                        save_config && print_message "SUCCESS" "Админы сохранены. Бот подхватит список автоматически." || print_message "ERROR" "Не удалось сохранить конфигурацию"
                    else
                        print_message "ERROR" "Только цифры и запятые"
                    fi
                fi
                ;;
            5)
                menu_reset
                if [[ "$KEEP_MODE" == "days" ]]; then
                    menu_add 1 "По файлам — оставлять последние N"
                    menu_add 2 "По дням — удалять старше N дней  ✓ сейчас"
                else
                    menu_add 1 "По файлам — оставлять последние N  ✓ сейчас"
                    menu_add 2 "По дням — удалять старше N дней"
                fi
                menu_choose input
                case "$input" in
                    1)
                        ui_input input "Сколько файлов хранить (1–200)" "$KEEP_FILES" || return 1
                        input="${input:-$KEEP_FILES}"
                        if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= 200 )); then
                            KEEP_FILES="$input"
                            KEEP_MODE="files"
                            save_config && print_message "SUCCESS" "Хранение по файлам: ${KEEP_FILES} шт." || print_message "ERROR" "Не удалось сохранить конфигурацию"
                        else
                            print_message "ERROR" "Число от 1 до 200"
                        fi
                        ;;
                    2)
                        ui_input input "Сколько дней хранить (1–365)" "${KEEP_DAYS:-7}" || return 1
                        input="${input:-7}"
                        if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= 365 )); then
                            KEEP_DAYS="$input"
                            KEEP_MODE="days"
                            save_config && print_message "SUCCESS" "Хранение по дням: ${KEEP_DAYS} дн." || print_message "ERROR" "Не удалось сохранить конфигурацию"
                        else
                            print_message "ERROR" "Число от 1 до 365"
                        fi
                        ;;
                esac
                ;;
            0) return ;;
        esac
        echo ""
        ui_pause
    done
}

show_main_status() {
    local version cron_txt tg_state archives remote keep_txt
    local -a rows
    version="$(local_version)"
    archives=$(find "$BACKUP_DIR" -maxdepth 1 -name 'rw_db_backup_*.sql.gz' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$KEEP_MODE" == "days" ]]; then
        keep_txt="${KEEP_DAYS} дн."
    else
        keep_txt="${KEEP_FILES} шт."
    fi
    cron_txt="${YELLOW}выключен${RESET}"
    (( CRON_HOURS > 0 )) && cron_txt="${BOLD}каждые ${CRON_HOURS} ч${RESET}"
    if [[ -z "$BOT_TOKEN" ]]; then
        tg_state="${YELLOW}не настроен · пункт 4${RESET}"
    elif bot_service_active; then
        tg_state="${GREEN}подключён · служба работает${RESET}"
    elif bot_service_installed; then
        tg_state="${RED}служба остановлена${RESET}"
    else
        tg_state="${YELLOW}токен задан · служба не установлена${RESET}"
    fi
    rows=(
        "База данных" "${BOLD}${DB_CONTAINER}${RESET}"
        "Архивы" "${BOLD}${archives}${RESET}${LIGHT_GRAY} · ${keep_txt}${RESET}"
        "Автобэкап" "$cron_txt"
        "Telegram" "$tg_state"
    )
    remote="$(remote_version)"
    if [[ -n "$remote" ]] && version_compare "$version" "$remote"; then
        rows+=("Обновление" "${YELLOW}доступна v${remote#v} · пункт 6${RESET}")
    fi
    ui_status_card "${GREEN}${BOLD}RW-BACK${RESET}  ${LIGHT_GRAY}by CyberERROR · v${version}${RESET}" "${rows[@]}"
}

main_menu() {
    while true; do
        load_config
        clear 2>/dev/null || true
        show_main_status
        echo ""
        menu_reset
        menu_add 1 "Создать бэкап сейчас" primary
        menu_add 2 "Восстановить из архива" primary
        menu_gap
        menu_add 3 "Список архивов"
        menu_add 4 "Telegram-бот"
        menu_add 5 "Настройки"
        menu_add 6 "Проверить обновление" warn
        menu_gap
        menu_add 7 "Удалить rw-back" danger
        menu_gap
        menu_add 0 "Выход"
        menu_footer "Быстрый запуск: ${MUTED_GREEN}rw-back${RESET}${LIGHT_GRAY} доступен из любой точки системы${RESET}"
        menu_footer "Документация: https://github.com/CyberERROR/rw-back"
        local choice
        menu_choose choice "${choice:-}"
        echo ""
        case "$choice" in
            1) menu_backup ;;
            2) menu_restore ;;
            3) menu_list ;;
            4) menu_bot ;;
            5) menu_settings ;;
            6) do_update || true; echo ""; ui_pause ;;
            7) do_remove || true; echo ""; ui_pause ;;
            0) echo "Выход..."; exit 0 ;;
        esac
    done
}

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
                ui_box "УСТАНОВКА RW-BACK"
                install_deps
                install_self
                wizard || return 1
                echo ""
                if finish_telegram_setup; then
                    print_message "SUCCESS" "Установка завершена. Открываю меню…"
                else
                    print_message "WARN" "Открываю меню: локальные функции готовы, Telegram требует внимания"
                fi
                sleep 1
            fi
            migrate_bot_service || print_message "WARN" "Службу старого формата обновить не удалось"
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
            wizard || return 1
            finish_telegram_setup || return 1
            print_message "SUCCESS" "Готово. Запустите: rw-back"
            ;;
        admin-code) cmd_admin_code ;;
        update)
            shift
            do_update "$@"
            ;;
        bot-install) install_bot_service ;;
        bot-remove) remove_bot_service ;;
        remove|uninstall) do_remove ;;
        version|--version|-v) local_version; echo ;;
        -h|--help|help) usage ;;
        *) usage; exit 1 ;;
    esac
}

main "$@"

#!/usr/bin/env bash

# ============================================================
# Logging utilities for seqfetcher
# ============================================================

# -------------------------------
# Defaults
# -------------------------------
LOG_LEVEL="INFO"     # DEBUG < INFO < WARN < ERROR
LOG_FILE="${LOG_FILE:-}"

# -------------------------------
# Color handling (only if TTY)
# -------------------------------
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    NC=$'\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

# -------------------------------
# Internal helpers
# -------------------------------

_log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

_log_level_value() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

_should_log() {
    local msg_level="$1"
    [[ $(_log_level_value "$msg_level") -ge $(_log_level_value "$LOG_LEVEL") ]]
}

_log_to_file() {
    [[ -n "$LOG_FILE" ]] || return 0
    echo "[$(_log_timestamp)] [$1] $2" >> "$LOG_FILE"
}

# -------------------------------
# Public logging functions
# -------------------------------

log_info() {
    _should_log INFO || return 0
    local msg="$*"
    printf "%b\n" "${GREEN}[INFO]${NC} $msg"
    _log_to_file INFO "$msg"
}

log_warn() {
    _should_log WARN || return 0
    local msg="$*"
    printf "%b\n" "${YELLOW}[WARN]${NC} $msg"
    _log_to_file WARN "$msg"
}

log_error() {
    _should_log ERROR || return 0
    local msg="$*"
    printf "%b\n" "${RED}[ERROR]${NC} $msg" >&2
    _log_to_file ERROR "$msg"
}

log_step() {
    _should_log INFO || return 0
    local msg="== $* =="
    printf "\n%b\n\n" "${BLUE}${msg}${NC}"
    _log_to_file INFO ""
    _log_to_file INFO "$msg"
}

log_debug() {
    [[ "$VERBOSE" == true ]] || return 0
    _should_log DEBUG || return 0
    local msg="$*"
    printf "%b\n" "${BLUE}[DEBUG]${NC} $msg"
    _log_to_file DEBUG "$msg"
}

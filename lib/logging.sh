#!/usr/bin/env bash

# Logging + error handling.
#
# CONTRACT: every log_* function writes to STDERR. stdout is reserved for a
# command's machine-readable payload (a results table, an SRR list, or the
# --json object). Downstream code and pipelines can therefore do
# `seqfetcher ... --json 2>/dev/null | jq .` and get clean JSON.
#
# Colour is emitted only when stderr is a TTY and NO_COLOR is unset
# (https://no-color.org). QUIET=true (from --quiet) silences the
# informational levels but never warnings or errors.

if [[ -z "${NO_COLOR:-}" && -t 2 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

log_info() {
    [[ "${QUIET:-false}" == true ]] && return 0
    echo -e "${GREEN}[INFO]${NC}  $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC}  $*" >&2
}
# lib/downloaders/ensembl_download.sh calls `log_warn` in a couple of places;
# keep an alias so those don't silently vanish.
log_warn() { log_warning "$@"; }

log_step() {
    [[ "${QUIET:-false}" == true ]] && return 0
    {
        echo
        echo -e "${CYAN}==================================================${NC}"
        echo -e "${CYAN}[STEP]${NC} $*"
        echo -e "${CYAN}==================================================${NC}"
        echo
    } >&2
}

log_success() {
    [[ "${QUIET:-false}" == true ]] && return 0
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

# die <message> [exit_code]
# Logs an error and exits. With --json, also emits a machine-readable error
# object on stdout first so a wrapper parsing stdout still sees the failure.
die() {
    local msg="$1"
    local code="${2:-${EX_ERROR:-1}}"
    if [[ "${JSON_OUTPUT:-false}" == true ]] && command -v jq >/dev/null 2>&1; then
        jq -n --arg m "$msg" --argjson c "$code" \
            '{status: "error", exit_code: $c, errors: [$m]}'
    fi
    log_error "$msg"
    exit "$code"
}

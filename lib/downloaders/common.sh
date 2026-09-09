#!/usr/bin/env bash

downloaders_common::prepare_download_environment() {
    mkdir -p "$OUTDIR"
    mkdir -p "$TEMP_DIR"

    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR

    trap downloaders_common::cleanup_temp EXIT
}

downloaders_common::cleanup_temp() {
    if [[ -d "$TEMP_DIR" ]]; then
        log_info "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

downloaders_common::is_help() {
    [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]
}

downloaders_common::check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command not found: $1"
        log_error "Please install $1 and try again"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Integrity / idempotency / atomic-write helpers
#
# atomic_fetch / new_stage+promote guarantee a destination is only ever
# created from a fully downloaded (and, where possible, checksum-verified)
# payload - a killed job leaves a *.part file or a staging dir under
# TEMP_DIR, never a half-written file/dir at the real path.
#
# already_have is the skip-by-default gate: with FORCE=true it always
# returns false; otherwise a present + verified file means "skip".
# ---------------------------------------------------------------------------

# downloaders_common::md5 <file>   - portable md5 (Linux md5sum / macOS md5)
downloaders_common::md5() {
    local f="$1"
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$f" 2>/dev/null | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q "$f" 2>/dev/null
    fi
}

downloaders_common::_bytes() {
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null
}

# downloaders_common::already_have <dest> [expected_md5] [expected_bytes]
#   0 -> present and good, caller should skip
#   1 -> absent, unverifiable-mismatch, or FORCE
downloaders_common::already_have() {
    local dest="$1" md5="${2:-}" bytes="${3:-}"
    [[ "${FORCE:-false}" == true ]] && return 1
    [[ -s "$dest" ]] || return 1

    if [[ -n "$md5" ]]; then
        local got; got="$(downloaders_common::md5 "$dest")"
        [[ "$got" == "$md5" ]] && return 0
        log_warning "$(basename "$dest"): checksum differs from expected - refetching"
        return 1
    fi
    if [[ -n "$bytes" ]]; then
        [[ "$(downloaders_common::_bytes "$dest")" == "$bytes" ]] && return 0
        log_warning "$(basename "$dest"): size differs from expected - refetching"
        return 1
    fi
    log_warning "$(basename "$dest"): already present but no checksum to verify against - keeping (use --force to refetch)"
    return 0
}

# downloaders_common::atomic_fetch <url> <dest> [expected_md5]
#   Downloads to <dest>.part (resumable), verifies, then renames into place.
#   On success sets LAST_FETCH_MD5 / LAST_FETCH_BYTES.
#   Returns EX_NETWORK on download failure, EX_INTEGRITY on checksum mismatch.
downloaders_common::atomic_fetch() {
    local url="$1" dest="$2" expected_md5="${3:-}"
    local part="${dest}.part"
    LAST_FETCH_MD5="" LAST_FETCH_BYTES=""

    mkdir -p "$(dirname "$dest")"

    if ! curl -fL --retry 3 --retry-delay 2 --retry-connrefused \
            -C - -o "$part" "$url"; then
        # -C - fails on a 0-byte / absent range restart with some servers;
        # retry once from scratch before giving up.
        rm -f "$part"
        if ! curl -fL --retry 3 --retry-delay 2 -o "$part" "$url"; then
            rm -f "$part"
            log_error "Download failed: $url"
            return "${EX_NETWORK:-5}"
        fi
    fi

    if [[ -n "$expected_md5" ]]; then
        local got; got="$(downloaders_common::md5 "$part")"
        if [[ "$got" != "$expected_md5" ]]; then
            log_error "Checksum mismatch for $(basename "$dest") (expected $expected_md5, got $got)"
            rm -f "$part"
            return "${EX_INTEGRITY:-6}"
        fi
    fi

    mv -f "$part" "$dest"
    LAST_FETCH_MD5="$(downloaders_common::md5 "$dest")"
    LAST_FETCH_BYTES="$(downloaders_common::_bytes "$dest")"
    return 0
}

# downloaders_common::new_stage - prints a fresh staging dir under TEMP_DIR
downloaders_common::new_stage() {
    mkdir -p "${TEMP_DIR:-temp_downloads}"
    mktemp -d "${TEMP_DIR:-temp_downloads}/stage.XXXXXX"
}

# downloaders_common::promote <staging_dir> <dest_dir>
#   Atomically replaces <dest_dir> with the contents of <staging_dir>.
downloaders_common::promote() {
    local stage="$1" dest="$2"
    [[ -d "$stage" ]] || { log_error "promote: staging dir missing: $stage"; return 1; }
    mkdir -p "$(dirname "$dest")"
    rm -rf "${dest}.replacing" 2>/dev/null
    [[ -e "$dest" ]] && mv "$dest" "${dest}.replacing"
    if mv "$stage" "$dest"; then
        rm -rf "${dest}.replacing" 2>/dev/null
        return 0
    fi
    [[ -e "${dest}.replacing" ]] && mv "${dest}.replacing" "$dest"
    return 1
}

# downloaders_common::batch_exit_code <successful> <failed>
#   0 all ok | EX_PARTIAL some ok + some failed | EX_NETWORK none ok
downloaders_common::batch_exit_code() {
    local ok="$1" bad="$2"
    (( bad == 0 )) && return 0
    (( ok  == 0 )) && return "${EX_NETWORK:-5}"
    return "${EX_PARTIAL:-7}"
}

export -f downloaders_common::md5 downloaders_common::_bytes \
          downloaders_common::already_have downloaders_common::atomic_fetch \
          downloaders_common::new_stage downloaders_common::promote \
          downloaders_common::batch_exit_code 2>/dev/null || true
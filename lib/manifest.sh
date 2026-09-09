#!/usr/bin/env bash

# Provenance / lockfile helpers.
#
# Every run writes to a single merged lockfile at <outdir>/seqfetcher.lock.json:
#
#   {
#     "schema": 1,
#     "seqfetcher_version": "1.1.0",
#     "runs": [ { command, argv, started_at, finished_at, status, exit_code,
#                 tool_versions } ],
#     "artifacts": {
#       "GCF_000005845.2:assembly": {
#         accession, type, source, source_url, db_release, requested_at,
#         status, files: [ { path, bytes, md5 } ], tool: { datasets: "..." }
#       }
#     }
#   }
#
# The lockfile is the download checkpoint: manifest::get lets a downloader
# skip an artifact already recorded as "downloaded". Writes are serialised
# with a lock (flock, or a mkdir spin-lock where flock is absent) because
# they happen from GNU parallel workers and background jobs.
#
# All functions are prefixed manifest:: and are export -f'd at the bottom
# so `parallel` / subshell workers can call them.

# ---------------------------------------------------------------------------
# init / context
# ---------------------------------------------------------------------------

# manifest::init <outdir>
manifest::init() {
    local outdir="${1:-${OUTDIR:-downloads}}"
    mkdir -p "$outdir" 2>/dev/null || true
    LOCKFILE="${outdir}/seqfetcher.lock.json"
    MANIFEST_RUN="$(mktemp "${TMPDIR:-/tmp}/seqfetcher-run.XXXXXX")"
    MANIFEST_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    export LOCKFILE MANIFEST_RUN MANIFEST_STARTED

    if command -v jq >/dev/null 2>&1 && [[ ! -f "$LOCKFILE" ]]; then
        jq -n --arg v "${SEQFETCHER_VERSION:-unknown}" \
            '{schema: 1, seqfetcher_version: $v, runs: [], artifacts: {}}' \
            > "$LOCKFILE" 2>/dev/null || true
    fi
}

# manifest::set_context <command> <argv...>
manifest::set_context() {
    MANIFEST_CMD="$1"; shift
    MANIFEST_ARGV=("$@")
    export MANIFEST_CMD
}

# ---------------------------------------------------------------------------
# locking
# ---------------------------------------------------------------------------

# manifest::_with_lock <command...>   - run <command> holding the lockfile lock
manifest::_with_lock() {
    [[ -z "${LOCKFILE:-}" ]] && { "$@"; return $?; }
    if command -v flock >/dev/null 2>&1; then
        (
            flock 9 || exit 1
            "$@"
        ) 9>"${LOCKFILE}.lock"
    else
        # portable fallback: mkdir is atomic
        local lockdir="${LOCKFILE}.lock.d" tries=0
        until mkdir "$lockdir" 2>/dev/null; do
            (( tries++ > 500 )) && break
            sleep 0.05
        done
        "$@"
        local rc=$?
        rmdir "$lockdir" 2>/dev/null || true
        return $rc
    fi
}

# ---------------------------------------------------------------------------
# tool versions (captured once per process)
# ---------------------------------------------------------------------------

manifest::tool_versions() {
    [[ -n "${_MANIFEST_TOOLVERS:-}" ]] && { printf '%s' "$_MANIFEST_TOOLVERS"; return 0; }
    command -v jq >/dev/null 2>&1 || { printf '{}'; return 0; }

    local datasets_v="" curl_v="" jq_v=""
    command -v datasets >/dev/null 2>&1 && datasets_v="$(datasets --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)"
    command -v curl     >/dev/null 2>&1 && curl_v="$(curl --version 2>/dev/null | head -n1 | awk '{print $2}')"
    jq_v="$(jq --version 2>/dev/null | sed 's/^jq-//')"

    _MANIFEST_TOOLVERS="$(jq -n \
        --arg s "${SEQFETCHER_VERSION:-unknown}" \
        --arg d "$datasets_v" --arg c "$curl_v" --arg j "$jq_v" \
        '{seqfetcher: $s}
         + (if $d != "" then {datasets: $d} else {} end)
         + (if $c != "" then {curl: $c} else {} end)
         + (if $j != "" then {jq: $j} else {} end)')"
    export _MANIFEST_TOOLVERS
    printf '%s' "$_MANIFEST_TOOLVERS"
}

# ---------------------------------------------------------------------------
# record / query artifacts
# ---------------------------------------------------------------------------

# manifest::record <key> <json-object>
#   merges the object into .artifacts[<key>] and appends it to the per-run
#   accumulator. A missing "requested_at" is filled in.
manifest::record() {
    local key="$1" entry="$2"
    command -v jq >/dev/null 2>&1 || return 0
    echo "$entry" | jq -e . >/dev/null 2>&1 || {
        log_warning "manifest::record got invalid JSON for $key - skipping"
        return 0
    }
    manifest::_with_lock manifest::_record_locked "$key" "$entry"
}

# manifest::record_run_only <key> <json>
#   Appends to the per-run summary (so --json / counts see it) WITHOUT
#   rewriting the lockfile artifact. Use for "skipped" so a re-run never
#   downgrades a recorded "downloaded" entry (and its checksums).
manifest::record_run_only() {
    local key="$1" entry="$2"
    command -v jq >/dev/null 2>&1 || return 0
    echo "$entry" | jq -e . >/dev/null 2>&1 || return 0
    local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -cn --arg k "$key" --arg ts "$now" --argjson e "$entry" \
        '$e + {key: $k, requested_at: ($e.requested_at // $ts)}' >> "$MANIFEST_RUN"
}

manifest::_record_locked() {
    local key="$1" entry="$2"
    local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local full
    full="$(jq -cn --arg k "$key" --arg ts "$now" --argjson e "$entry" \
        '$e + {key: $k, requested_at: ($e.requested_at // $ts)}')"

    printf '%s\n' "$full" >> "$MANIFEST_RUN"

    [[ -f "$LOCKFILE" ]] || return 0
    local tmp="${LOCKFILE}.tmp.$$"
    if jq --arg k "$key" --argjson e "$full" '.artifacts[$k] = $e' \
        "$LOCKFILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$LOCKFILE"
    else
        rm -f "$tmp"
        log_warning "Failed to update $LOCKFILE for $key"
    fi
}

# manifest::get <key>  - prints .artifacts[<key>] or nothing
manifest::get() {
    local key="$1"
    [[ -f "${LOCKFILE:-/nonexistent}" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    local out
    out="$(jq -c --arg k "$key" '.artifacts[$k] // empty' "$LOCKFILE" 2>/dev/null)"
    [[ -n "$out" ]] || return 1
    printf '%s\n' "$out"
}

# manifest::stored_md5 <key>  - prints the first recorded file md5 for <key>
manifest::stored_md5() {
    manifest::get "$1" 2>/dev/null | jq -r '.files[0].md5 // empty' 2>/dev/null
}

# manifest::is_done <key>  - true if <key> was recorded as downloaded
manifest::is_done() {
    local st
    st="$(manifest::get "$1" 2>/dev/null | jq -r '.status // empty' 2>/dev/null)"
    [[ "$st" == "downloaded" ]]
}

# ---------------------------------------------------------------------------
# run record + final emit
# ---------------------------------------------------------------------------

# manifest::add_run <status> <exit_code>
manifest::add_run() {
    local status="$1" code="${2:-0}"
    command -v jq >/dev/null 2>&1 || return 0
    [[ -f "${LOCKFILE:-/nonexistent}" ]] || return 0
    manifest::_with_lock manifest::_add_run_locked "$status" "$code"
}

manifest::_add_run_locked() {
    local status="$1" code="${2:-0}"
    local now argv_json tv tmp
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    argv_json="$(printf '%s\n' "${MANIFEST_ARGV[@]}" | jq -R . | jq -s .)"
    tv="$(manifest::tool_versions)"
    tmp="${LOCKFILE}.tmp.$$"
    if jq \
        --arg cmd "${MANIFEST_CMD:-unknown}" \
        --arg started "${MANIFEST_STARTED:-$now}" \
        --arg finished "$now" \
        --arg status "$status" \
        --argjson code "$code" \
        --argjson argv "$argv_json" \
        --argjson tv "$tv" \
        '.runs += [{command: $cmd, argv: $argv, started_at: $started,
                    finished_at: $finished, status: $status,
                    exit_code: $code, tool_versions: $tv}]' \
        "$LOCKFILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$LOCKFILE"
    else
        rm -f "$tmp"
    fi
}

# manifest::emit <status> <exit_code>
#   prints the per-run summary object to stdout (only when --json).
manifest::emit() {
    [[ "${JSON_OUTPUT:-false}" == true ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    local status="$1" code="${2:-0}"
    local runfile="${MANIFEST_RUN:-/dev/null}"
    [[ -f "$runfile" ]] || runfile=/dev/null

    jq -s \
        --arg ver "${SEQFETCHER_VERSION:-unknown}" \
        --arg cmd "${MANIFEST_CMD:-unknown}" \
        --arg status "$status" \
        --argjson code "$code" \
        --arg outdir "${OUTDIR:-downloads}" \
        --arg lockfile "${LOCKFILE:-}" \
        '# collapse repeated records for the same key, keeping the last
         (reduce .[] as $i ({}; .[$i.key] = $i) | [.[]]) as $items
         | {
            seqfetcher_version: $ver,
            command: $cmd,
            status: $status,
            exit_code: $code,
            outdir: $outdir,
            lockfile: $lockfile,
            counts: {
                total:      ($items | length),
                downloaded: ($items | map(select(.status == "downloaded")) | length),
                skipped:    ($items | map(select(.status == "skipped"))    | length),
                failed:     ($items | map(select(.status == "failed"))     | length)
            },
            items: $items
        }' "$runfile"
}

# manifest::cleanup  - drop the per-run temp accumulator
manifest::cleanup() {
    [[ -n "${MANIFEST_RUN:-}" && -f "${MANIFEST_RUN}" ]] && rm -f "$MANIFEST_RUN"
    return 0
}

export -f manifest::init manifest::set_context manifest::_with_lock \
          manifest::tool_versions manifest::record manifest::_record_locked \
          manifest::get manifest::stored_md5 manifest::is_done manifest::record_run_only \
          manifest::add_run manifest::_add_run_locked manifest::emit \
          manifest::cleanup 2>/dev/null || true

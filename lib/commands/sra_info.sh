#!/usr/bin/env bash

commands_sra_info::execute_sra_info() {
    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR
    mkdir -p "$TEMP_DIR"

    trap downloaders_common::cleanup_temp EXIT

    downloaders_sra_info_download::create_runinfo_table "$@"
    local result=$?

    downloaders_common::cleanup_temp
    return $result
}

commands_sra_info::emit_json() {
    local status="$1" code="$2"
    command -v jq >/dev/null 2>&1 || return 0
    local list="${SRA_INFO_OUT:-$OUTDIR/tables/sra_runinfo_runs.txt}"
    local meta="${SRA_INFO_META:-$OUTDIR/tables/sra_runinfo.tsv}"
    local runs='[]'
    [[ -s "$list" ]] && runs="$(jq -R -s 'split("\n") | map(select(length > 0))' "$list")"
    jq -n --arg ver "${SEQFETCHER_VERSION:-unknown}" --arg status "$status" \
          --argjson code "$code" --arg outdir "$OUTDIR" \
          --arg list "$list" --arg meta "$meta" --argjson runs "$runs" \
        '{seqfetcher_version: $ver, command: "sra-info", status: $status,
          exit_code: $code, outdir: $outdir,
          files: {run_list: $list, metadata_tsv: $meta},
          count: ($runs | length), runs: $runs}'
}

commands_sra_info::run_sra_info() {
    # --outdir is parsed inside the downloader; mirror it into OUTDIR up front
    # so the lockfile and --json 'outdir' land in the right place.
    local _a _prev=""
    for _a in "$@"; do
        [[ "$_prev" == "--outdir" ]] && OUTDIR="$_a"
        _prev="$_a"
    done

    manifest::init "$OUTDIR"
    manifest::set_context sra-info "$@"

    local rc=0
    commands_sra_info::execute_sra_info "$@" || rc=$?

    local status="success"
    [[ $rc -ne 0 ]] && status="error"

    manifest::add_run "$status" "$rc"
    [[ "${JSON_OUTPUT:-false}" == true ]] && commands_sra_info::emit_json "$status" "$rc"
    manifest::cleanup
    return "$rc"
}

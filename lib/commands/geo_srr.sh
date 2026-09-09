#!/usr/bin/env bash

commands_geo_srr::execute_geo_srr() {
    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR
    mkdir -p "$TEMP_DIR"

    trap downloaders_common::cleanup_temp EXIT

    downloaders_geo_download::create_srr_list_from_geo "$@"
    local result=$?

    downloaders_common::cleanup_temp
    return $result
}

# --json payload: the resolved SRR list + the metadata table it produced.
commands_geo_srr::emit_json() {
    local status="$1" code="$2"
    command -v jq >/dev/null 2>&1 || return 0
    local list="${GEO_SRR_OUT:-$OUTDIR/tables/GEO_SRR_list.txt}"
    local meta="${GEO_SRR_META:-$OUTDIR/tables/GEO_SRR_list_metadata.tsv}"
    local runs='[]'
    [[ -s "$list" ]] && runs="$(jq -R -s 'split("\n") | map(select(length > 0))' "$list")"
    jq -n --arg ver "${SEQFETCHER_VERSION:-unknown}" --arg status "$status" \
          --argjson code "$code" --arg outdir "$OUTDIR" \
          --arg list "$list" --arg meta "$meta" --argjson runs "$runs" \
        '{seqfetcher_version: $ver, command: "geo-srr", status: $status,
          exit_code: $code, outdir: $outdir,
          files: {run_list: $list, metadata_tsv: $meta},
          count: ($runs | length), runs: $runs}'
}

commands_geo_srr::run_geo_srr() {
    manifest::init "$OUTDIR"
    manifest::set_context geo-srr "$@"

    local rc=0
    commands_geo_srr::execute_geo_srr "$@" || rc=$?

    local status="success"
    [[ $rc -ne 0 ]] && status="error"

    manifest::add_run "$status" "$rc"
    [[ "${JSON_OUTPUT:-false}" == true ]] && commands_geo_srr::emit_json "$status" "$rc"
    manifest::cleanup
    return "$rc"
}

#!/usr/bin/env bash

commands_bioproject_srr::execute_bioproject_srr() {
    export OUTPUT_DIR="$OUTDIR"
    export TEMP_DIR
    mkdir -p "$TEMP_DIR"

    trap downloaders_common::cleanup_temp EXIT

    downloaders_bioproject_download::create_srr_list_from_bioproject "$@"
    local result=$?

    downloaders_common::cleanup_temp
    return $result
}

commands_bioproject_srr::emit_json() {
    local status="$1" code="$2"
    command -v jq >/dev/null 2>&1 || return 0
    local list="${BP_SRR_OUT:-$OUTDIR/tables/BioProject_SRR_list.txt}"
    local meta="${BP_SRR_META:-$OUTDIR/tables/BioProject_SRR_list_metadata.tsv}"
    local runs='[]'
    [[ -s "$list" ]] && runs="$(jq -R -s 'split("\n") | map(select(length > 0))' "$list")"
    jq -n --arg ver "${SEQFETCHER_VERSION:-unknown}" --arg status "$status" \
          --argjson code "$code" --arg outdir "$OUTDIR" \
          --arg list "$list" --arg meta "$meta" --argjson runs "$runs" \
        '{seqfetcher_version: $ver, command: "bp-srr", status: $status,
          exit_code: $code, outdir: $outdir,
          files: {run_list: $list, metadata_tsv: $meta},
          count: ($runs | length), runs: $runs}'
}

commands_bioproject_srr::run_bioproject_srr() {
    manifest::init "$OUTDIR"
    manifest::set_context bp-srr "$@"

    local rc=0
    commands_bioproject_srr::execute_bioproject_srr "$@" || rc=$?

    local status="success"
    [[ $rc -ne 0 ]] && status="error"

    manifest::add_run "$status" "$rc"
    [[ "${JSON_OUTPUT:-false}" == true ]] && commands_bioproject_srr::emit_json "$status" "$rc"
    manifest::cleanup
    return "$rc"
}

#!/usr/bin/env bash

downloaders_ortholog::run_ortholog_download() {

    downloaders_common::prepare_download_environment

    log_info "Starting ortholog download"

    local input

    if [[ "$ORTHOLOG_USER" == true ]]; then

        local tmp
        tmp=$(mktemp)

        echo "$ORTHOLOG" |
            tr ',' '\n' > "$tmp"

        input="$tmp"

    else

        input="$ORTHOLOG_FILE"

    fi

    local rc=0
    downloaders_ortholog_download::download_orthologs_batch \
        "$input" \
        "$OUTDIR" \
        "$PARALLEL_JOBS" || rc=$?

    [[ "$ORTHOLOG_USER" == true ]] &&
        rm -f "$tmp"

    downloaders_common::cleanup_temp
    return "$rc"
}

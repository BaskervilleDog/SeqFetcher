#!/usr/bin/env bash

downloaders_proteome::run_proteome_download() {

    downloaders_common::prepare_download_environment

    export ENSEMBL_TYPE ENSEMBL_RELEASE FORCE REQUIRE_PINNED PROTEOME_ID

    local rc=0
    if [[ "$PROTEOME_SOURCE" == "uniprot" ]]; then
        downloaders_uniprot_download::download_proteome "$PROTEOME_ID" "$OUTDIR" || rc=$?
    else
        downloaders_ensembl_download::download_proteome \
            "$PROTEOME_ASSEMBLY" \
            "$PROTEOME_SPECIES" \
            "$PROTEOME_SOURCE" \
            "$PROTEOME_TYPE" || rc=$?
    fi

    downloaders_common::cleanup_temp
    return "$rc"
}

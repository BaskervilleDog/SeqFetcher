#!/usr/bin/env bash

downloaders_proteome::run_proteome_download() {

    downloaders_common::prepare_download_environment

    export ENSEMBL_TYPE ENSEMBL_RELEASE FORCE REQUIRE_PINNED

    local rc=0
    downloaders_ensembl_download::download_proteome \
        "$PROTEOME_ASSEMBLY" \
        "$PROTEOME_SPECIES" \
        "$PROTEOME_SOURCE" \
        "$PROTEOME_TYPE" || rc=$?

    downloaders_common::cleanup_temp
    return "$rc"
}

#!/usr/bin/env bash

downloaders_transcriptome::run_transcriptome_download() {

    downloaders_common::prepare_download_environment

    export ENSEMBL_TYPE ENSEMBL_RELEASE FORCE REQUIRE_PINNED

    local rc=0
    downloaders_ensembl_download::download_transcriptome \
        "$TRANSCRIPTOME_ASSEMBLY" \
        "$TRANSCRIPTOME_SPECIES" \
        "$TRANSCRIPTOME_SOURCE" \
        "$TRANSCRIPTOME_TYPE" || rc=$?

    downloaders_common::cleanup_temp
    return "$rc"
}

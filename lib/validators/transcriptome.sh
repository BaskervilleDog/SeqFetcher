#!/usr/bin/env bash

validators_transcriptome::validate_transcriptome_download() {

    [[ -z "$TRANSCRIPTOME_ASSEMBLY" &&
       -z "$TRANSCRIPTOME_SPECIES" ]] &&
    {
        log_error "Transcriptome requires --assembly or --species"
        return "${EX_USAGE:-2}"
    }

    return 0
}
#!/usr/bin/env bash

validators_proteome::validate_proteome_download() {

    [[ -z "$PROTEOME_ASSEMBLY" &&
       -z "$PROTEOME_SPECIES" ]] &&
    {
        log_error "Proteome requires --assembly or --species"
        exit 1
    }

    return 0
}
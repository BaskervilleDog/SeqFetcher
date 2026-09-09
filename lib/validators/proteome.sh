#!/usr/bin/env bash

validators_proteome::validate_proteome_download() {

    if [[ "$PROTEOME_SOURCE" == "uniprot" ]]; then
        [[ -z "$PROTEOME_ID" ]] &&
        {
            log_error "--source uniprot requires --proteome-id UPXXXXXXXXX"
            return "${EX_USAGE:-2}"
        }
        [[ ! "$PROTEOME_ID" =~ ^UP[0-9]{9}$ ]] &&
        {
            log_error "Invalid UniProt proteome id: $PROTEOME_ID (expected UP + 9 digits)"
            return "${EX_USAGE:-2}"
        }
        return 0
    fi

    [[ -z "$PROTEOME_ASSEMBLY" &&
       -z "$PROTEOME_SPECIES" ]] &&
    {
        log_error "Proteome requires --assembly or --species (or --source uniprot --proteome-id)"
        return "${EX_USAGE:-2}"
    }

    return 0
}

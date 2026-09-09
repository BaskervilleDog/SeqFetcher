#!/usr/bin/env bash

validators_ortholog::validate_ortholog_download() {

    [[ "$ORTHOLOG_USER" == false &&
       "$ORTHOLOG_FILE_USER" == false ]] &&
    {
        log_error "Must specify --ortholog or --ortholog-file"
        return "${EX_USAGE:-2}"
    }

    [[ "$ORTHOLOG_FILE_USER" == true &&
       ! -f "$ORTHOLOG_FILE" ]] &&
    {
        log_error "Ortholog accession file not found: $ORTHOLOG_FILE"
        return "${EX_USAGE:-2}"
    }

    return 0
}

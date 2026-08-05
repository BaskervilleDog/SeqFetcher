#!/usr/bin/env bash

validators_gene::validate_gene_download() {

    [[ "$GENE_ID_USER" == false &&
       "$GENE_FILE_USER" == false ]] &&
    {
        log_error "Must specify --gene-id or --gene-file"
        exit 1
    }

    [[ "$GENE_FILE_USER" == true &&
       ! -f "$GENE_FILE" ]] &&
    {
        log_error "Gene file not found: $GENE_FILE"
        exit 1
    }

    return 0
}
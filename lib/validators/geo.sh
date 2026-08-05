#!/usr/bin/env bash

validators_geo::validate_geo_download() {

    [[ -z "$GEO_ACCESSION" ]] &&
    {
        log_error "Must specify --geo GSEXXXXX"
        exit 1
    }

    return 0
}
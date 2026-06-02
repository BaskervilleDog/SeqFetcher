#!/usr/bin/env bash

validate_geo_download() {

    [[ -z "$GEO_ACCESSION" ]] &&
    {
        log_error "Must specify --geo GSEXXXXX"
        exit 1
    }
}
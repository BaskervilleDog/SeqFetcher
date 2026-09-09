#!/usr/bin/env bats
# Unit tests for the per-source accession-format validators that live next
# to their downloader rather than in lib/validators/ (they validate a
# format, not a set of CLI options, so lib/downloaders/*.sh owns them).

load 'test_helper'

# --- downloaders_bioproject_download::validate_bioproject_accession -----

@test "accepts PRJNA/PRJEB/PRJDB accessions" {
    run downloaders_bioproject_download::validate_bioproject_accession "PRJNA1173518"
    [ "$status" -eq 0 ]
    run downloaders_bioproject_download::validate_bioproject_accession "PRJEB12345"
    [ "$status" -eq 0 ]
    run downloaders_bioproject_download::validate_bioproject_accession "PRJDB12345"
    [ "$status" -eq 0 ]
}

@test "rejects an empty or malformed BioProject accession" {
    run downloaders_bioproject_download::validate_bioproject_accession ""
    [ "$status" -eq 2 ]
    run downloaders_bioproject_download::validate_bioproject_accession "PRJXX12345"
    [ "$status" -eq 2 ]
}

# --- downloaders_geo_download::validate_geo_accession --------------------

@test "accepts a well-formed GEO series accession" {
    run downloaders_geo_download::validate_geo_accession "GSE280953"
    [ "$status" -eq 0 ]
}

@test "rejects an empty or malformed GEO accession" {
    run downloaders_geo_download::validate_geo_accession ""
    [ "$status" -eq 2 ]
    run downloaders_geo_download::validate_geo_accession "GSM12345"
    [ "$status" -eq 2 ]
}

# --- downloaders_sra_download::validate_sra_accession ---------------------

@test "accepts SRR/ERR/DRR accessions" {
    downloaders_sra_download::validate_sra_accession "SRR12345678"
    downloaders_sra_download::validate_sra_accession "ERR12345678"
    downloaders_sra_download::validate_sra_accession "DRR12345678"
}

@test "rejects an unrelated accession prefix" {
    ! downloaders_sra_download::validate_sra_accession "GCF_000005845.2"
}

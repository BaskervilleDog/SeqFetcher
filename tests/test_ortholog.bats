#!/usr/bin/env bats
# Unit tests for lib/downloaders/ortholog_download.sh - scoped to the
# deterministic, offline pieces (accession-type detection, the Gene ID
# passthrough branch, and the elink-JSON parser) per docs/CONVENTIONS.md.
# resolve_gene_id's protein/nucleotide branches and fetch_orthologs itself
# call NCBI Entrez/Datasets and aren't covered here.

load 'test_helper'

# --- detect_accession_type -----------------------------------------------

@test "detect_accession_type recognizes RefSeq protein prefixes" {
    [ "$(downloaders_ortholog_download::detect_accession_type NP_001416352.1)" = "protein" ]
    [ "$(downloaders_ortholog_download::detect_accession_type XP_123456.1)" = "protein" ]
    [ "$(downloaders_ortholog_download::detect_accession_type WP_123456.1)" = "protein" ]
}

@test "detect_accession_type recognizes RefSeq nucleotide prefixes" {
    [ "$(downloaders_ortholog_download::detect_accession_type NM_001429423.1)" = "nucleotide" ]
    [ "$(downloaders_ortholog_download::detect_accession_type XM_123456.1)" = "nucleotide" ]
    [ "$(downloaders_ortholog_download::detect_accession_type NG_123456.1)" = "nucleotide" ]
}

@test "detect_accession_type recognizes a numeric Gene ID" {
    [ "$(downloaders_ortholog_download::detect_accession_type 672)" = "gene_id" ]
}

@test "detect_accession_type reports unknown for an unrecognized format" {
    run downloaders_ortholog_download::detect_accession_type GCF_000005845.2
    [[ "$output" == *"unknown"* ]]
    [[ "$output" == *"Unrecognized ortholog accession format"* ]]
}

# --- resolve_gene_id -------------------------------------------------------

@test "resolve_gene_id passes a Gene ID through unchanged" {
    [ "$(downloaders_ortholog_download::resolve_gene_id 672 gene_id)" = "672" ]
}

@test "resolve_gene_id fails on an unrecognized type" {
    run downloaders_ortholog_download::resolve_gene_id foo unknown
    [ "$status" -eq 1 ]
}

# --- _elink_first_id (elink JSON parsing) ---------------------------------

@test "_elink_first_id picks the link under an accepted linkname" {
    result=$(echo '{
        "linksets": [{
            "linksetdbs": [
                {"linkname": "protein_gene_abstract", "links": ["999"]},
                {"linkname": "protein_gene", "links": ["672"]}
            ]
        }]
    }' | downloaders_ortholog_download::_elink_first_id "protein_gene protein_gene_refseq")
    [ "$result" = "672" ]
}

@test "_elink_first_id prints nothing when no linksetdb matches" {
    result=$(echo '{"linksets":[{"linksetdbs":[{"linkname":"protein_gene_abstract","links":["999"]}]}]}' |
        downloaders_ortholog_download::_elink_first_id "protein_gene protein_gene_refseq")
    [ -z "$result" ]
}

@test "_elink_first_id prints nothing for an empty linksets array" {
    result=$(echo '{"linksets":[]}' | downloaders_ortholog_download::_elink_first_id "protein_gene")
    [ -z "$result" ]
}

# --- fetch_orthologs cache path (the one branch that's offline) ----------

@test "fetch_orthologs reports the cached count without re-downloading" {
    local fasta="$BATS_TEST_TMPDIR/cached.fasta"
    printf '>acc1 desc\nMKV\n>acc2 desc\nMKW\n' > "$fasta"
    run downloaders_ortholog_download::fetch_orthologs 672 "$fasta" "NP_test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using cached ortholog FASTA (2 sequences)"* ]]
}

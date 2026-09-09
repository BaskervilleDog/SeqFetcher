#!/usr/bin/env bats
# Unit tests for lib/validators/*.sh - each function reads global option
# variables (set by lib/parsers/*.sh in real usage) and exit 1 with a
# log_error message when a required option is missing.

load 'test_helper'

setup() {
    reset_config
}

# --- validators_search ------------------------------------------------

@test "validators_search::validate_search_inputs fails without --organism" {
    run validators_search::validate_search_inputs
    [ "$status" -eq 2 ]
    [[ "$output" == *"Missing --organism"* ]]
}

@test "validators_search::validate_search_inputs defaults OUTPUT_FILE under OUTDIR/tables" {
    ORGANISM="E. coli"
    validators_search::validate_search_inputs
    [ "$OUTPUT_FILE" = "${OUTDIR}/tables/assemblies.tsv" ]
}

@test "validators_search::validate_search_inputs rejects a non-numeric --top" {
    ORGANISM="E. coli"
    TOP_N="lots"
    run validators_search::validate_search_inputs
    [ "$status" -eq 2 ]
    [[ "$output" == *"Invalid --top"* ]]
}

@test "validators_search::validate_search_inputs rejects --top 0" {
    ORGANISM="E. coli"
    TOP_N=0
    run validators_search::validate_search_inputs
    [ "$status" -eq 2 ]
}

@test "validators_search::validate_search_inputs accepts a positive --top" {
    ORGANISM="E. coli"
    TOP_N=200
    run validators_search::validate_search_inputs
    [ "$status" -eq 0 ]
}

@test "validators_search::validate_search_inputs defaults OUTPUT_FILE to tables/gene_ids.txt when extracting genes" {
    ORGANISM="E. coli"
    EXTRACT_GENES=true
    validators_search::validate_search_inputs
    [ "$OUTPUT_FILE" = "${OUTDIR}/tables/gene_ids.txt" ]
}

@test "validators_search::validate_search_inputs --pdb needs a filter" {
    MODE="pdb"
    run validators_search::validate_search_inputs
    [ "$status" -eq 2 ]
}

@test "validators_search::validate_search_inputs --pdb accepts --organism and defaults the table path" {
    MODE="pdb"; ORGANISM="Homo sapiens"
    validators_search::validate_search_inputs
    [ "$OUTPUT_FILE" = "${OUTDIR}/tables/pdb_structures.tsv" ]
}

@test "validators_search::validate_search_inputs --pdb rejects a bad --method / --max-resolution / --sort" {
    MODE="pdb"; ORGANISM="Homo sapiens"
    SEARCH_METHOD="bogus"
    run validators_search::validate_search_inputs
    [ "$status" -eq 2 ]

    reset_config; MODE="pdb"; ORGANISM="Homo sapiens"; SEARCH_MAX_RESOLUTION="abc"
    run validators_search::validate_search_inputs
    [ "$status" -eq 2 ]

    reset_config; MODE="pdb"; ORGANISM="Homo sapiens"; SEARCH_SORT="sideways"
    run validators_search::validate_search_inputs
    [ "$status" -eq 2 ]
}

@test "validators_search::validate_search_inputs --alphafold needs a filter" {
    MODE="alphafold"
    run validators_search::validate_search_inputs
    [ "$status" -eq 2 ]
}

@test "validators_search::validate_search_inputs --alphafold accepts --gene and defaults the table path" {
    MODE="alphafold"; SEARCH_GENE="TP53"
    validators_search::validate_search_inputs
    [ "$OUTPUT_FILE" = "${OUTDIR}/tables/alphafold_structures.tsv" ]
}

@test "validators_search::validate_search_inputs rejects an unknown --mode" {
    MODE="galaxy"; ORGANISM="E. coli"
    run validators_search::validate_search_inputs
    [ "$status" -eq 2 ]
}

# --- validators_assembly -----------------------------------------------

@test "validators_assembly::validate_assembly_download fails without --accession/--accession-file" {
    run validators_assembly::validate_assembly_download
    [ "$status" -eq 2 ]
}

@test "validators_assembly::validate_assembly_download fails when accession file doesn't exist" {
    ACCESSION_FILE="$BATS_TEST_TMPDIR/nope.txt"
    run validators_assembly::validate_assembly_download
    [ "$status" -eq 2 ]
    [[ "$output" == *"not found"* ]]
}

@test "validators_assembly::validate_assembly_download passes with a single accession" {
    ACCESSION="GCF_000005845.2"
    run validators_assembly::validate_assembly_download
    [ "$status" -eq 0 ]
}

# --- validators_annotation --------------------------------------------

@test "validators_annotation::validate_annotation_download fails without an accession" {
    run validators_annotation::validate_annotation_download
    [ "$status" -eq 2 ]
}

@test "validators_annotation::validate_annotation_download rejects a bad --annotation-formats value" {
    ACCESSION="GCF_000005845.2"
    ANNOTATION_FORMATS="gff3,fasta"
    run validators_annotation::validate_annotation_download
    [ "$status" -eq 2 ]
    [[ "$output" == *"annotation-formats"* ]]
}

@test "validators_annotation::validate_annotation_download passes with an accession and gff3,gtf" {
    ACCESSION="GCF_000005845.2"
    ANNOTATION_FORMATS="gff3,gtf"
    run validators_annotation::validate_annotation_download
    [ "$status" -eq 0 ]
}

# --- validators_structure --------------------------------------------

@test "validators_structure::validate_structure_download fails with no ids" {
    run validators_structure::validate_structure_download
    [ "$status" -eq 2 ]
}

@test "validators_structure::validate_structure_download rejects a bad --format" {
    STRUCTURE_PDB="1TUP"
    STRUCTURE_FORMAT="fasta"
    run validators_structure::validate_structure_download
    [ "$status" -eq 2 ]
}

@test "validators_structure::validate_structure_download rejects a malformed PDB id" {
    STRUCTURE_PDB="1TU"
    run validators_structure::validate_structure_download
    [ "$status" -eq 2 ]
}

@test "validators_structure::validate_structure_download passes with --pdb 1TUP" {
    STRUCTURE_PDB="1TUP"
    run validators_structure::validate_structure_download
    [ "$status" -eq 0 ]
}

@test "validators_structure::validate_structure_download passes with --alphafold P04637" {
    STRUCTURE_ALPHAFOLD="P04637"
    run validators_structure::validate_structure_download
    [ "$status" -eq 0 ]
}

# --- validators_gene -----------------------------------------------

@test "validators_gene::validate_gene_download fails without --gene-id/--gene-file" {
    run validators_gene::validate_gene_download
    [ "$status" -eq 2 ]
}

@test "validators_gene::validate_gene_download passes with GENE_ID_USER set" {
    GENE_ID_USER=true
    run validators_gene::validate_gene_download
    [ "$status" -eq 0 ]
}

# --- validators_ortholog -----------------------------------------------

@test "validators_ortholog::validate_ortholog_download fails without --ortholog/--ortholog-file" {
    run validators_ortholog::validate_ortholog_download
    [ "$status" -eq 2 ]
}

@test "validators_ortholog::validate_ortholog_download fails when ortholog file doesn't exist" {
    ORTHOLOG_FILE_USER=true
    ORTHOLOG_FILE="$BATS_TEST_TMPDIR/nope.txt"
    run validators_ortholog::validate_ortholog_download
    [ "$status" -eq 2 ]
    [[ "$output" == *"not found"* ]]
}

@test "validators_ortholog::validate_ortholog_download passes with ORTHOLOG_USER set" {
    ORTHOLOG_USER=true
    run validators_ortholog::validate_ortholog_download
    [ "$status" -eq 0 ]
}

# --- validators_sra -----------------------------------------------

@test "validators_sra::validate_sra_download fails without --sra-method" {
    run validators_sra::validate_sra_download
    [ "$status" -eq 2 ]
    [[ "$output" == *"--sra-method"* ]]
}

@test "validators_sra::validate_sra_download fails without an accession once method is set" {
    SRA_METHOD="fasterq"
    run validators_sra::validate_sra_download
    [ "$status" -eq 2 ]
    [[ "$output" == *"--sra-accession"* ]]
}

@test "validators_sra::validate_sra_download passes with method and accession" {
    SRA_METHOD="fasterq"
    ACCESSION="SRR12345678"
    run validators_sra::validate_sra_download
    [ "$status" -eq 0 ]
}

# --- validators_geo / validators_bioproject -----------------------------

@test "validators_geo::validate_geo_download fails without --geo" {
    run validators_geo::validate_geo_download
    [ "$status" -eq 2 ]
}

@test "validators_bioproject::validate_bioproject_srr fails without --bioproject" {
    run validators_bioproject::validate_bioproject_srr
    [ "$status" -eq 2 ]
}

# --- validators_ensembl / transcriptome / proteome ----------------------

@test "validators_ensembl::validate_ensembl_download requires --species and --type" {
    run validators_ensembl::validate_ensembl_download
    [ "$status" -eq 2 ]
    [[ "$output" == *"--species"* ]]

    ENSEMBL_SPECIES="homo_sapiens"
    run validators_ensembl::validate_ensembl_download
    [ "$status" -eq 2 ]
    [[ "$output" == *"--type"* ]]

    ENSEMBL_TYPE="cdna"
    run validators_ensembl::validate_ensembl_download
    [ "$status" -eq 0 ]
}

@test "validators_transcriptome::validate_transcriptome_download requires --assembly or --species" {
    run validators_transcriptome::validate_transcriptome_download
    [ "$status" -eq 2 ]

    TRANSCRIPTOME_SPECIES="homo_sapiens"
    run validators_transcriptome::validate_transcriptome_download
    [ "$status" -eq 0 ]
}

@test "validators_proteome::validate_proteome_download requires --assembly or --species" {
    run validators_proteome::validate_proteome_download
    [ "$status" -eq 2 ]

    PROTEOME_ASSEMBLY="GCF_000005845.2"
    run validators_proteome::validate_proteome_download
    [ "$status" -eq 0 ]
}

@test "validators_proteome::validate_proteome_download requires --proteome-id when --source uniprot" {
    PROTEOME_SOURCE="uniprot"
    run validators_proteome::validate_proteome_download
    [ "$status" -eq 2 ]

    PROTEOME_ID="not-an-id"
    run validators_proteome::validate_proteome_download
    [ "$status" -eq 2 ]

    PROTEOME_ID="UP000005640"
    run validators_proteome::validate_proteome_download
    [ "$status" -eq 0 ]
}

# --- validators_download (dispatcher) ------------------------------------

@test "validators_download::validate_download_inputs dispatches to the assembly validator" {
    DOWNLOAD_TYPE="assembly"
    ACCESSION="GCF_000005845.2"
    run validators_download::validate_download_inputs
    [ "$status" -eq 0 ]
}

@test "validators_download::validate_download_inputs dispatches to the ortholog validator" {
    DOWNLOAD_TYPE="ortholog"
    ORTHOLOG_USER=true
    run validators_download::validate_download_inputs
    [ "$status" -eq 0 ]
}

@test "validators_download::validate_download_inputs rejects an unknown DOWNLOAD_TYPE" {
    DOWNLOAD_TYPE="not-a-real-type"
    run validators_download::validate_download_inputs
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown download type"* ]]
}

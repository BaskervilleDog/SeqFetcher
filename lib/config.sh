#!/usr/bin/env bash


# If using WSL and having problems with DNS connection to datasets API:
# 1. Stop WSL from overwriting DNS
# sudo nano /etc/wsl.conf
# Add:
# [network]
# generateResolvConf = false
#
# 2. Replace DNS manually
# sudo rm /etc/resolv.conf
# echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
# echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
#
# 3. Restart WSL fully (From Windows Powershell)
# wsl --shutdown



# Single source of truth for the version string (shown in --version, the
# help banner, and recorded in seqfetcher.lock.json).
SEQFETCHER_VERSION="1.2.0"

# =====================================
# General defaults
# =====================================

MODE="assemblies"
OUTDIR="downloads"
OUTPUT_FILE=""
TEMP_DIR="temp_downloads"
PARALLEL_JOBS=4
THREADS=4

# --- global behaviour flags (set by the pre-parse in seqfetcher.sh) ---
JSON_OUTPUT=false    # --json      : emit a machine-readable object on stdout
QUIET=false          # --quiet/-q  : silence [INFO]/[STEP]/[SUCCESS] on stderr
FORCE=false          # --force     : re-download even if the lockfile has it
REQUIRE_PINNED=false # --require-pinned : refuse sources that resolve "latest"

# =====================================
# Search
# =====================================

ORGANISM=""
INTERACTIVE=false
EXTRACT_GENES=false
# How many top-ranked assemblies to display and write to the results table.
TOP_N=50

# =====================================
# Assembly downloads
# =====================================

ACCESSION=""
ACCESSION_FILE=""

# =====================================
# Gene downloads
# =====================================

GENE_FILE=""
GENE_FILE_USER=false
GENE_ID=""
GENE_ID_USER=false

# =====================================
# Download dispatcher
# =====================================

DOWNLOAD_TYPE="assembly"

# =====================================
# SRA
# =====================================

SRA_METHOD=""

# =====================================
# GEO
# =====================================

GEO_ACCESSION=""

# =====================================
# Ensembl
# =====================================

ENSEMBL_FASTA=false
ENSEMBL_SPECIES=""
ENSEMBL_TYPE=""
ENSEMBL_RELEASE=""

# =====================================
# Transcriptome
# =====================================

TRANSCRIPTOME=false
TRANSCRIPTOME_ASSEMBLY=""
TRANSCRIPTOME_SPECIES=""
TRANSCRIPTOME_SOURCE="ncbi"
TRANSCRIPTOME_TYPE="cdna"

# =====================================
# Annotation-only downloads
# =====================================

ANNOTATION=false
ANNOTATION_FORMATS="gff3,gtf"   # subset of gff3,gtf,gbff

# =====================================
# Proteome
# =====================================

PROTEOME=false
PROTEOME_ASSEMBLY=""
PROTEOME_SPECIES=""
PROTEOME_SOURCE="ncbi"          # ncbi | ensembl | auto | uniprot
PROTEOME_TYPE="pep"
PROTEOME_ID=""                  # UniProt proteome id (with --source uniprot)

# =====================================
# Structure downloads (AlphaFold / RCSB PDB)
# =====================================

STRUCTURE=false
STRUCTURE_ALPHAFOLD=""          # comma-separated UniProt accessions
STRUCTURE_ALPHAFOLD_FILE=""
STRUCTURE_PDB=""                # comma-separated PDB ids
STRUCTURE_PDB_FILE=""
STRUCTURE_FORMAT="pdb"          # pdb | cif

# =====================================
# BioProject
# =====================================

BIOPROJECT_ACCESSION=""

# =====================================
# Ortholog downloads
# =====================================

ORTHOLOG=""
ORTHOLOG_USER=false
ORTHOLOG_FILE=""
ORTHOLOG_FILE_USER=false

# Optional. Raises the NCBI Entrez rate limit from 3 to 10 req/s.
# Register free at: https://www.ncbi.nlm.nih.gov/account/
NCBI_API_KEY="${NCBI_API_KEY:-}"
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



# =====================================
# General defaults
# =====================================

MODE="assemblies"
OUTDIR="downloads"
OUTPUT_FILE=""
TEMP_DIR="temp_downloads"
PARALLEL_JOBS=4
THREADS=4

# =====================================
# Search
# =====================================

ORGANISM=""
INTERACTIVE=false
EXTRACT_GENES=false

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
# Proteome
# =====================================

PROTEOME=false
PROTEOME_ASSEMBLY=""
PROTEOME_SPECIES=""
PROTEOME_SOURCE="ncbi"
PROTEOME_TYPE="pep"

# =====================================
# BioProject
# =====================================

BIOPROJECT_ACCESSION=""
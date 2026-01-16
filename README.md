---
title: "seqfetcher"
output: github_document
---

## seqfetcher

**seqfetcher** is a unified command-line tool for downloading **RNA-seq data, genomes, transcriptomes, and proteomes** from public biological databases, with automatic fallback between **NCBI, ENA, GEO, and Ensembl**.

It is designed for:

- RNA-seq analysis pipelines  
- Bioinformatics portfolio projects  
- Reproducible data acquisition  
- High-throughput sequencing workflows  

---

## Features

- Download RNA-seq FASTQ from:
  - ENA
  - SRA
  - GEO (auto-resolves to SRR)
- Download genomes, transcriptomes, and proteomes
- Automatic Ensembl fallback when NCBI data is unavailable
- Parallel FASTQ downloads
- Accession list support (batch mode)
- Clean directory structure
- Robust logging and error handling

---

## Installation

### Requirements

Ensure the following tools are installed:

- `bash >= 4.0`
- `wget`
- `curl`
- `unzip`
- `parallel` (optional, recommended)
- `sra-tools` (`fasterq-dump`)
- `ncbi-datasets-cli` (`datasets`)

---

## Commands Overview

| Command | Description |
|------|------------|
| `download rnaseq` | Download RNA-seq FASTQ files |
| `download genome` | Download genome assemblies |
| `download transcriptome` | Download transcriptome FASTA |
| `download proteome` | Download protein FASTA |

---

## Download RNA-seq from ENA

```bash
seqfetcher download rnaseq \
  --accession SRR1234567 \
  --source ena

Output

data/rnaseq/SRR1234567/
├── SRR1234567_1.fastq.gz
└── SRR1234567_2.fastq.gz

Download RNA-seq from SRA

seqfetcher download rnaseq \
  --accession SRR1234567 \
  --source sra

Download RNA-seq from GEO

seqfetcher download rnaseq \
  --accession GSE280953

Automatically:

    Resolves GEO → SRR

    Downloads all runs

    Organizes per-sample directories

Parallel RNA-seq Download

seqfetcher download rnaseq \
  --accession SRP012345 \
  --source ena \
  --parallel 6

RNA-seq Batch Download (List of Accessions)

Create a file runs.txt:

SRR1234567
SRR1234568
SRR1234569

Run:

seqfetcher download rnaseq \
  --accession-file runs.txt \
  --source ena

Genome Downloads
Download a Genome from NCBI

seqfetcher download genome \
  --accession GCF_000001635.27

Output

data/genomes/GCF_000001635.27/
├── *.fna
├── *.gff
└── assembly_report.txt

Download Genomes from a List of Accessions

seqfetcher download genome \
  --accession-file genomes.txt

Where genomes.txt contains:

GCF_000001635.27
GCA_000001405.29

Transcriptome Downloads
Download Transcriptome from NCBI

seqfetcher download transcriptome \
  --accession GCF_000001635.27

Transcriptome with Ensembl Fallback

seqfetcher download transcriptome \
  --accession GCF_000001635.27 \
  --species mus_musculus \
  --fallback ensembl

Proteome Downloads
Download Proteome from NCBI

seqfetcher download proteome \
  --accession GCF_000001635.27

Proteome with Ensembl Fallback

seqfetcher download proteome \
  --accession GCF_000001635.27 \
  --species homo_sapiens \
  --fallback ensembl


# Download FASTQ with retry and resume
./seqfetcher download fastq \
  --accessions SRR_list.txt \
  --source ena \
  --threads 16 \
  --verbose

# Search and download genome interactively
./seqfetcher download genome \
  --organism "Mus musculus" \
  --filter reference \
  --include genome,gff,pep,cdna

# Dry-run to test
./seqfetcher download genome \
  --assembly GCF_000001635.27 \
  --include genome \
  --dry-run

# Download with Ensembl fallback
./seqfetcher download transcriptome \
  --assembly GCF_000001635.27 \
  --species mus_musculus \
  --fallback ensembl \
  --max-retries 5
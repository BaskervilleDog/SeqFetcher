# SeqFetcher

A unified command-line tool for searching and downloading genomic data from multiple databases including NCBI, ENA, GEO, and Ensembl.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)

## Overview

SeqFetcher simplifies genomic data retrieval by providing a unified interface to multiple databases and data types.

### Key Features

✨ **Unified Interface** - Single command for all genomic data sources
🚀 **Parallel Downloads** - Speed up large batch downloads
🔍 **Smart Search** - Rank results by quality (RefSeq, reference genomes, assembly level)
📊 **Rich Metadata** - Extract taxonomy and gene information
✅ **Robust Validation** - MD5 checksums and file size verification
🎯 **Multiple Sources** - NCBI, ENA, GEO, Ensembl support
🧬 **Comprehensive Data** - Assemblies, genes, transcriptomes, proteomes, orthologs, and sequencing reads

### Supported Data Sources

| Source | Data Types | Features |
|--------|------------|----------|
| **NCBI** | Assemblies, genes, SRA reads, orthologs | Reference genomes, annotations |
| **ENA** | FASTQ files | Direct download, MD5 verification |
| **GEO** | Supplementary files, SRA links | Expression data, metadata |
| **Ensembl** | Transcriptomes, proteomes, FASTA | Latest releases, multiple species |

---

## Installation

### Prerequisites

| Tool | Required For | Installation |
|------|-------------|--------------|
| **NCBI Datasets** | Assembly/gene downloads | [Download](https://www.ncbi.nlm.nih.gov/datasets/docs/v2/download-and-install/) |
| **jq** | JSON parsing | `brew install jq` or `apt-get install jq` |
| **GNU Parallel** | Parallel downloads | `brew install parallel` or `apt-get install parallel` |
| **SRA Toolkit** | SRA downloads (optional) | [Download](https://github.com/ncbi/sra-tools/wiki/02.-Installing-SRA-Toolkit) |
| **wget/curl** | File downloads | Usually pre-installed |

`bash scripts/check_deps.sh` checks all of the above (plus `curl`,
`python3`, and the coreutils SeqFetcher relies on) in one pass and reports
exactly what's missing - run it before anything else on a new machine.

### Install SeqFetcher

```bash
# Clone the repository
git clone https://github.com/BaskervilleDog/seqfetcher.git
cd seqfetcher

# Confirm dependencies are on PATH
bash scripts/check_deps.sh

# Run installation
chmod +x install.sh
./install.sh

# Add to PATH
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

### Verify Installation

```bash
seqfetcher --help
```

---

## Quick Start

### Search for genomes

```bash
seqfetcher search --organism "Saccharomyces cerevisiae"
```

### Download a reference genome

```bash
seqfetcher download --accession GCF_000005845.2
```

### Download SRA data

```bash
seqfetcher download --sra-method fasterq --sra-accession SRR12345678
```

### Download from GEO

```bash
# Download supplementary files
seqfetcher download --geo GSE280953

# Extract SRA run list
seqfetcher geo-srr --geo GSE280953 --out runs.txt

# Download the sequencing data
seqfetcher download --sra-method fasterq --sra-accession-file runs.txt
```

### Download transcriptome

```bash
seqfetcher download --transcriptome --species homo_sapiens --source auto
```

### Download orthologs for a gene

```bash
seqfetcher download --ortholog NP_001416352.1
```

For every option, every command, common multi-step workflows, and file
formats, see the **[Command Reference](docs/COMMAND_REFERENCE.md)**.

---

## Documentation

- **[Command Reference](docs/COMMAND_REFERENCE.md)** - every option for
  every command, common workflows, output file formats
- **[Troubleshooting & Performance](docs/TROUBLESHOOTING.md)** - fixes for
  common errors, tuning large batch downloads
- **[Development Conventions](docs/CONVENTIONS.md)** - project layout,
  function naming, tests, dependency checking, function-graph generation -
  read this before adding a command, downloader, or test

## Project Structure

```
lib/
├── config.sh, logging.sh, validation.sh   Global state and cross-cutting utilities
├── commands/       One file per CLI subcommand (search, download, geo-srr, bp-srr)
├── parsers/        --flag parsing
├── validators/      Input validation before a command runs
└── downloaders/       NCBI / ENA / GEO / Ensembl / SRA download logic
tests/              bats-core - run with `bats tests/`
scripts/            check_deps.sh, generate_function_graph.sh
graphs/             auto-generated call & dependency graphs
docs/               everything above
```

See [docs/CONVENTIONS.md](docs/CONVENTIONS.md) for the reasoning behind
this layout.

---

## Citation

If you use SeqFetcher in your research:

```
SeqFetcher: A unified CLI for genomic data retrieval
GitHub: https://github.com/BaskervilleDog/seqfetcher
```

---

## License

MIT License - see [LICENSE](LICENSE) file for details

---

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Read [docs/CONVENTIONS.md](docs/CONVENTIONS.md)
3. Create a feature branch
4. Make your changes, adding a bats test alongside any new parser or validator
5. Run `bats tests/` and `bash scripts/check_deps.sh`
6. Submit a pull request

---

## Support

- **Issues**: [GitHub Issues](https://github.com/BaskervilleDog/seqfetcher/issues)
- **Documentation**: [Wiki](https://github.com/BaskervilleDog/seqfetcher/wiki)

---

## Changelog

### Version 1.0.0 (2026-01-22)
- Initial release
- NCBI assemblies, genes, SRA support
- ENA direct download
- GEO integration
- Ensembl transcriptome/proteome support
- Parallel download capability
- Interactive search mode

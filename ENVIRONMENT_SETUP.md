# Environment Setup and Database Download Guide

This guide covers setting up conda environments and downloading the required databases for the metagenome analysis pipeline.

## Conda Environment Setup

### Alternative Conda Channel (Tsinghua Mirror)

> ⚠️ **Note:** If you cannot connect to the official conda channels (conda-forge, bioconda), you can use the Tsinghua University mirror as an alternative:
> 
> **Mirror URL:** https://mirrors.tuna.tsinghua.edu.cn/
> 
> To configure conda to use the Tsinghua mirror, add the following to your `~/.condarc` file:
> ```yaml
> channels:
>   - defaults
> show_channel_urls: true
> default_channels:
>   - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
>   - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
>   - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
> custom_channels:
>   conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
>   bioconda: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
> ```

### Creating Environments from YAML Files

Pre-configured environment YAML files are provided in the `env_files/` directory:

```bash
# Create environments from YAML files
conda env create -f env_files/kneaddata_env.yml
conda env create -f env_files/kraken_env.yml
conda env create -f env_files/humann3_env.yml

# Create sra-tools environment
conda create -n sra-tools -c bioconda sra-tools
```

### Manual Environment Creation

If you prefer to create environments manually:

```bash
# SRA Tools for downloading data
conda create -n sra-tools -c bioconda sra-tools

# Kneaddata for host removal
conda create -n kneaddata -c bioconda kneaddata

# Kraken2 for taxonomic classification
conda create -n kraken2.1.3 -c bioconda kraken2=2.1.3 bracken

# HUMAnN3 for functional profiling (includes MetaPhlAn)
conda create -n humann3 -c bioconda humann
```

---

## Database Downloads

**Total storage needed: ~130 GB**

> ⚠️ **Important:** Download all databases BEFORE running the pipeline. Database downloads can take several hours depending on your internet connection.

### 1. Kneaddata Database (Human Genome hg39)

Used for host contamination removal. Downloads the human reference genome (hg39).

```bash
# Create database directory
mkdir -p $DATABASE_DIR/kneaddata/human
cd $DATABASE_DIR/kneaddata/human

# Download human genome database (hg39) (~6 GB, ~30 min)
wget http://huttenhower.sph.harvard.edu/kneadData_databases/Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz

# Extract the database files
tar -xzvf Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz

# Optional: Remove archive to save space
rm Homo_sapiens_hg39_T2T_Bowtie2_v0.1.tar.gz

# Verify installation
ls $DATABASE_DIR/kneaddata/human/
# Should see the following bowtie2 index files:
#   hg_39.1.bt2
#   hg_39.2.bt2
#   hg_39.3.bt2
#   hg_39.4.bt2
#   hg_39.rev.1.bt2
#   hg_39.rev.2.bt2
```

**Config setting:**
```bash
KNEADDATA_DB="${DATABASE_DIR}/kneaddata/human/hg_39"
```

### 2. Kraken2 Database (PlusPF)

Used for taxonomic classification. The PlusPF database includes bacteria, archaea, viruses, plasmids, human, protozoa, and fungi.

```bash
# Create database directory
mkdir -p $DATABASE_DIR/kraken2

# Download PlusPF database (~70 GB, ~2-4 hours)
cd $DATABASE_DIR/kraken2
wget https://genome-idx.s3.amazonaws.com/kraken/k2_pluspf_20240904.tar.gz

# Extract (requires ~70 GB additional space during extraction)
mkdir -p pluspf
tar -xzf k2_pluspf_20240904.tar.gz -C pluspf
rm k2_pluspf_20240904.tar.gz  # Optional: remove archive to save space

# Verify installation
ls $DATABASE_DIR/kraken2/pluspf/
# Should see: hash.k2d, opts.k2d, taxo.k2d, seqid2taxid.map, etc.
```

**Config setting:**
```bash
KRAKEN2_DB="${DATABASE_DIR}/kraken2/pluspf"
```

### 3. HUMAnN3 Databases

HUMAnN3 requires multiple databases for functional profiling.

#### 3a. ChocoPhlAn Database (Nucleotide)

```bash
# Activate humann3 environment
conda activate humann3

# Create database directory
mkdir -p $DATABASE_DIR/humann3

# Download full ChocoPhlAn database (~15 GB, ~1-2 hours)
humann_databases --download chocophlan full $DATABASE_DIR/humann3

# Verify installation
ls $DATABASE_DIR/humann3/chocophlan/
# Should see many .ffn.gz files
```

#### 3b. UniRef90 Diamond Database (Protein)

```bash
# Download UniRef90 database (~35 GB, ~2-4 hours)
humann_databases --download uniref uniref90_diamond $DATABASE_DIR/humann3

# Verify installation
ls $DATABASE_DIR/humann3/uniref/
# Should see: uniref90_201901b_full.dmnd (or similar)
```

#### 3c. Utility Mapping Database (Optional - for annotation)

This database is **not required** for the pipeline to run, but is needed to convert UniRef90 IDs to human-readable gene and pathway names in post-processing.

```bash
# Download utility mapping (~2.5 GB, ~15 min)
humann_databases --download utility_mapping full $DATABASE_DIR/humann3

# Verify installation
ls $DATABASE_DIR/humann3/utility_mapping/
# Should see: map_*.txt.gz files
```

**Config settings:**
```bash
HUMANN_NUC_DB="${DATABASE_DIR}/humann3/chocophlan"
HUMANN_PROT_DB="${DATABASE_DIR}/humann3/uniref"
```

### 4. MetaPhlAn Database

Used by HUMAnN3 for taxonomic profiling before functional analysis.

> ⚠️ **Critical:** The MetaPhlAn database version must be compatible with your HUMAnN3 installation. Using mismatched versions will cause errors.

```bash
# Create database directory
mkdir -p $DATABASE_DIR/metaphlan4
cd $DATABASE_DIR/metaphlan4

# Download the database files using wget (~1.5 GB total)
wget -c http://cmprod1.cibio.unitn.it/biobakery4/metaphlan_databases/mpa_vOct22_CHOCOPhlAnSGB_202403.tar
wget -c http://cmprod1.cibio.unitn.it/biobakery4/metaphlan_databases/bowtie2_indexes/mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar

# Extract the database files
tar -xf mpa_vOct22_CHOCOPhlAnSGB_202403.tar
tar -xf mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar

# Optional: Remove tar files to save space
rm mpa_vOct22_CHOCOPhlAnSGB_202403.tar mpa_vOct22_CHOCOPhlAnSGB_202403_bt2.tar

# Verify installation
ls $DATABASE_DIR/metaphlan4/
# Should see: mpa_vOct22_CHOCOPhlAnSGB_202403.* files
```

**Config setting:**
```bash
METAPHLAN_DB="${DATABASE_DIR}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403"
```

---

## Database Verification Checklist

After downloading all databases, verify your setup:

```bash
# Set your database directory (same as in config.sh)
DATABASE_DIR="/path/to/your/databases"

# Check all database directories exist and are not empty
echo "=== Checking databases ==="

# Kneaddata
[ -f "$DATABASE_DIR/kneaddata/human/hg_39.1.bt2" ] && echo "✓ Kneaddata OK" || echo "✗ Kneaddata MISSING"

# Kraken2
[ -f "$DATABASE_DIR/kraken2/pluspf/hash.k2d" ] && echo "✓ Kraken2 OK" || echo "✗ Kraken2 MISSING"

# HUMAnN3 ChocoPhlAn
[ -d "$DATABASE_DIR/humann3/chocophlan" ] && [ "$(ls -A $DATABASE_DIR/humann3/chocophlan)" ] && echo "✓ ChocoPhlAn OK" || echo "✗ ChocoPhlAn MISSING"

# HUMAnN3 UniRef
ls $DATABASE_DIR/humann3/uniref/*.dmnd &>/dev/null && echo "✓ UniRef OK" || echo "✗ UniRef MISSING"

# MetaPhlAn
[ -d "$DATABASE_DIR/metaphlan4" ] && ls $DATABASE_DIR/metaphlan4/*.pkl &>/dev/null && echo "✓ MetaPhlAn OK" || echo "✗ MetaPhlAn MISSING"
```

---

## Troubleshooting

### Database Issues

**1. "Database not found" errors**
- Verify paths in `config.sh` match actual locations
- Check file permissions (databases should be readable)
- For Kneaddata, point to the prefix (e.g., `hg_39`), not the directory

**2. "Killed" or out-of-memory during database download**
- Download on a compute node with more memory
- Use `wget` with `-c` (continue) flag to resume interrupted downloads

**3. Corrupted database files**
- Re-download the database
- Verify checksums if provided by the source

### Environment Issues

**1. Conda channel connection issues**
- Use the Tsinghua mirror as described at the beginning of this document
- Try `conda config --set ssl_verify false` if behind a proxy (not recommended for security)

**2. Package conflicts during environment creation**
- Use the provided YAML files which have pre-resolved dependencies
- Try using `mamba` instead of `conda` for faster dependency resolution:
  ```bash
  conda install -n base mamba
  mamba env create -f env_files/humann3_env.yml
  ```


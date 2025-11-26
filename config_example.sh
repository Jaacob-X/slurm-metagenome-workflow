#!/bin/bash

# Example configuration file for metagenome pipeline
# Copy this to config.sh and modify for your system

#================================================================
# PROJECT SETTINGS
#================================================================

PROJECT_ID=""
BASE_DIR=""
DATABASE_DIR=""
SAMPLE_LIST=""
NUM_SAMPLES=1

#================================================================
# DIRECTORY STRUCTURE
#================================================================

# Input/Output directories
RAW_DATA_DIR="${BASE_DIR}/raw_reads"
FASTQC_DIR="${BASE_DIR}/fastqc_results"
TRIMMED_DIR="${BASE_DIR}/trimmed_reads"
KNEADDATA_DIR="${BASE_DIR}/kneaddata_output"
KRAKEN2_DIR="${BASE_DIR}/kraken2_output"
HUMANN3_DIR="${BASE_DIR}/humann3_output"
LOGS_DIR="${BASE_DIR}/logs"

#================================================================
# ARRAY JOB SETTINGS (tunable based on cluster capacity)
#================================================================

# Adjust these based on your cluster's job limits and available resources
MAX_CONCURRENT_FASTQC=20
MAX_CONCURRENT_TRIMGALORE=20
MAX_CONCURRENT_KNEADDATA=20
MAX_CONCURRENT_KRAKEN2=20
MAX_CONCURRENT_HUMANN3=20 

#================================================================
# RESOURCE ALLOCATIONS (per sample)
#================================================================

# Download (sequential - not array)
DOWNLOAD_CPUS=4
DOWNLOAD_MEM=4G
DOWNLOAD_TIME=48:00:00

# FastQC
FASTQC_CPUS=4
FASTQC_MEM=8G
FASTQC_TIME=4:00:00

# Trim Galore
TRIMGALORE_CPUS=16
TRIMGALORE_MEM=32G
TRIMGALORE_TIME=8:00:00

# Kneaddata
KNEADDATA_CPUS=16
KNEADDATA_MEM=32G
KNEADDATA_TIME=12:00:00

# Kraken2
KRAKEN2_CPUS=16
KRAKEN2_MEM=64G
KRAKEN2_TIME=8:00:00

# HUMAnN3
HUMANN3_CPUS=32
HUMANN3_MEM=128G
HUMANN3_TIME=16:00:00

#================================================================
# SINGLE JOB SETTINGS (for processing all samples in one job)
#================================================================

# Single job time allocations (longer than array jobs since they process all samples)
# Note: These should be adjusted based on your sample count and cluster time limits
FASTQC_SINGLE_TIME=48:00:00        # All samples in one FastQC job
TRIMGALORE_SINGLE_TIME=120:00:00   # All samples in one Trim Galore job
KNEADDATA_SINGLE_TIME=120:00:00    # All samples in one Kneaddata job
KRAKEN2_SINGLE_TIME=120:00:00      # All samples in one Kraken2 job
HUMANN3_SINGLE_TIME=120:00:00      # All samples in one HUMAnN3 job

#================================================================
# SLURM DEFAULT SETTINGS
#================================================================

# Set your partition name
SLURM_PARTITION="normal"

# Set your account name if required by your cluster
SLURM_ACCOUNT=""

# Email for job notifications (optional)
SLURM_EMAIL="your.email@institution.edu"

#================================================================
# DATABASE PATHS (UPDATE THESE FOR YOUR SYSTEM)
#================================================================

# Kneaddata database (human genome for host removal)
# Example: "/path/to/kneaddata/database/human/hg_39"
KNEADDATA_DB="${DATABASE_DIR}/kneaddata/human/hg_39"

# Kraken2 database (taxonomic classification)
# Example: "/path/to/kraken2/database/pluspf"
KRAKEN2_DB="${DATABASE_DIR}/kraken2/pluspf"

# HUMAnN3 databases (functional profiling)
# Example: "/path/to/humann3/database/chocophlan"
HUMANN_NUC_DB="${DATABASE_DIR}/humann3/chocophlan"

# Example: "/path/to/humann3/database/uniref"
HUMANN_PROT_DB="${DATABASE_DIR}/humann3/uniref"

# Example: "/path/to/metaphlan/database/mpa_vOct22_CHOCOPhlAnSGB_202403"
METAPHLAN_DB="${DATABASE_DIR}/metaphlan4/mpa_vOct22_CHOCOPhlAnSGB_202403"

# Trimmomatic path (used by Kneaddata)
# IMPORTANT: This path is specific to YOUR kneaddata conda environment!
# To find your path, run:
#   conda activate kneaddata
#   echo $CONDA_PREFIX/share/trimmomatic-*/
# Then update the path below with your actual trimmomatic location.
TRIMMOMATIC_PATH=""  # <-- REQUIRED: Set this to your trimmomatic path

#================================================================
# TOOL PARAMETERS (extracted from original scripts)
#================================================================

# Trim Galore parameters
TRIMGALORE_QUALITY=0           # Minimum quality score
TRIMGALORE_STRINGENCY=5        # Overlap with adapter sequence required
TRIMGALORE_MIN_LENGTH=10       # Minimum read length after trimming

# FastQC parameters
FASTQC_THREADS=4               # Threads for FastQC

# Kneaddata parameters
KNEADDATA_THREADS=16           # Threads for Kneaddata

#================================================================
# SAMPLE PROCESSING OPTIONS
#================================================================

# Skip completed samples (auto-resume)
AUTO_RESUME=true

# Create output directories if they don't exist
CREATE_DIRS=true

# Verbose output
VERBOSE=true

#================================================================
# VALIDATION
#================================================================

# Validate configuration
validate_config() {
    local errors=0

    # Check if sample list exists
    if [[ ! -f "$SAMPLE_LIST" ]]; then
        echo "ERROR: Sample list file not found: $SAMPLE_LIST"
        ((errors++))
    fi

    # Check if base directory is accessible
    if [[ ! -d "$(dirname "$BASE_DIR")" ]]; then
        echo "ERROR: Cannot access base directory parent: $(dirname "$BASE_DIR")"
        ((errors++))
    fi

    # Check if database paths exist
    # KNEADDATA_DB is a bowtie2 index prefix, not a directory - check if index files exist
    if ! ls "${KNEADDATA_DB}".*.bt2 &>/dev/null; then
        echo "WARNING: Kneaddata database not found: $KNEADDATA_DB"
    fi

    if [[ ! -d "$KRAKEN2_DB" ]]; then
        echo "WARNING: Kraken2 database not found: $KRAKEN2_DB"
    fi

    if [[ ! -d "$HUMANN_NUC_DB" ]]; then
        echo "WARNING: HUMAnN3 nucleotide database not found: $HUMANN_NUC_DB"
    fi

    if [[ ! -d "$HUMANN_PROT_DB" ]]; then
        echo "WARNING: HUMAnN3 protein database not found: $HUMANN_PROT_DB"
    fi

    # Check Trimmomatic path (required for Kneaddata)
    if [[ -z "$TRIMMOMATIC_PATH" ]]; then
        echo "ERROR: TRIMMOMATIC_PATH is not set."
        echo "       To find your path, run: conda activate kneaddata && echo \$CONDA_PREFIX/share/trimmomatic-*/"
        ((errors++))
    elif [[ ! -d "$TRIMMOMATIC_PATH" ]]; then
        echo "ERROR: Trimmomatic directory not found: $TRIMMOMATIC_PATH"
        echo "       To find your path, run: conda activate kneaddata && echo \$CONDA_PREFIX/share/trimmomatic-*/"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        echo "Configuration validation failed with $errors errors"
        return 1
    fi

    echo "Configuration validation passed"
    return 0
}

# Create necessary directories
create_directories() {
    mkdir -p "$RAW_DATA_DIR" "$FASTQC_DIR" "$TRIMMED_DIR" "$KNEADDATA_DIR" "$KRAKEN2_DIR" "$HUMANN3_DIR" "$LOGS_DIR"
    echo "Created all necessary directories"
}

# Export all variables
export PROJECT_ID BASE_DIR DATABASE_DIR SAMPLE_LIST NUM_SAMPLES
export RAW_DATA_DIR FASTQC_DIR TRIMMED_DIR KNEADDATA_DIR KRAKEN2_DIR HUMANN3_DIR LOGS_DIR
export MAX_CONCURRENT_FASTQC MAX_CONCURRENT_TRIMGALORE MAX_CONCURRENT_KNEADDATA MAX_CONCURRENT_KRAKEN2 MAX_CONCURRENT_HUMANN3
export DOWNLOAD_CPUS DOWNLOAD_MEM DOWNLOAD_TIME
export FASTQC_CPUS FASTQC_MEM FASTQC_TIME
export TRIMGALORE_CPUS TRIMGALORE_MEM TRIMGALORE_TIME
export KNEADDATA_CPUS KNEADDATA_MEM KNEADDATA_TIME
export KRAKEN2_CPUS KRAKEN2_MEM KRAKEN2_TIME
export HUMANN3_CPUS HUMANN3_MEM HUMANN3_TIME
export FASTQC_SINGLE_TIME TRIMGALORE_SINGLE_TIME KNEADDATA_SINGLE_TIME KRAKEN2_SINGLE_TIME HUMANN3_SINGLE_TIME
export SLURM_PARTITION SLURM_ACCOUNT SLURM_EMAIL
export KNEADDATA_DB KRAKEN2_DB HUMANN_NUC_DB HUMANN_PROT_DB METAPHLAN_DB TRIMMOMATIC_PATH
export TRIMGALORE_QUALITY TRIMGALORE_STRINGENCY TRIMGALORE_MIN_LENGTH FASTQC_THREADS KNEADDATA_THREADS
export AUTO_RESUME CREATE_DIRS VERBOSE

# Run validation if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_config
    if [[ $? -eq 0 ]] && [[ "$CREATE_DIRS" == "true" ]]; then
        create_directories
    fi
fi
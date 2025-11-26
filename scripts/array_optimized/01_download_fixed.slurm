#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - FIXED SEQUENTIAL DOWNLOAD
#================================================================
# NOTE: Downloading is inherently sequential (one sample at a time) for network protection.
# Adjust partition and time based on your cluster configuration and sample count.
#SBATCH --job-name=download_fixed
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=4G
#SBATCH --time=48:00:00
#SBATCH --output=logs/download_%j.out
#SBATCH --error=logs/download_%j.err

#================================================================
# SCRIPT COMMANDS
#================================================================

echo "--- Job started on $(hostname) at $(date) ---"
echo "SLURM_JOB_ID: ${SLURM_JOB_ID}"

# --- 1. Set up your Conda environment ---
module load miniforge3
conda activate sra-tools

# --- 2. Source configuration ---
# Use SLURM_SUBMIT_DIR (directory where sbatch was run) to find config
source "${SLURM_SUBMIT_DIR}/config.sh"

echo "Output directory is: $RAW_DATA_DIR"
echo "SRR list file is: $SAMPLE_LIST"

# --- 3. Create output directory ---
mkdir -p "$RAW_DATA_DIR"
mkdir -p "$LOGS_DIR"

# --- 4. Main download loop ---
# Resumable: checks if final file exists before processing.
cat "$SAMPLE_LIST" | while read srr
do
  if [ -f "${RAW_DATA_DIR}/${srr}_1.fastq.gz" ] && [ -f "${RAW_DATA_DIR}/${srr}_2.fastq.gz" ]; then
    echo "--- SKIPPING ${srr}: Final compressed FASTQ files already exist. ---"
    continue
  fi

  echo "--- Processing ${srr} ---"

  # Download with prefetch
  echo "  Prefetching ${srr}..."
  prefetch "$srr"

  # Use fastq-dump with --gzip to download compressed files directly
  # Alternative: fasterq-dump $srr --split-files -O $RAW_DATA_DIR (no gzip)
  echo "  Downloading with fastq-dump --gzip..."
  fastq-dump "$srr" --split-3 --gzip -O "$RAW_DATA_DIR"

  # Verify files were created
  if [ -f "${RAW_DATA_DIR}/${srr}_1.fastq.gz" ] && [ -f "${RAW_DATA_DIR}/${srr}_2.fastq.gz" ]; then
    echo "  ✓ Successfully downloaded ${srr}"
  else
    echo "  ✗ ERROR: Failed to download ${srr}"
    ls -la "${RAW_DATA_DIR}/${srr}"*
  fi

done

echo "--- Job finished at $(date) ---"
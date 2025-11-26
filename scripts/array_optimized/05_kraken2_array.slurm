#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - KRAKEN2 ARRAY PROCESSING
#================================================================
# NOTE: SBATCH directives use default values. Adjust these directly or use
# sbatch command-line overrides (e.g., sbatch --cpus-per-task=32 script.slurm)
#SBATCH --job-name=kraken2_array
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=8:00:00

# --- JOB ARRAY DIRECTIVES ---
# IMPORTANT: Update --array parameter based on your sample count before submission
# Example: --array=1-74%4 for 74 samples with max 4 concurrent jobs
#SBATCH --array=1-2%4
#SBATCH --output=logs/kraken2_%A_%a.out
#SBATCH --error=logs/kraken2_%A_%a.err

#================================================================
# SCRIPT COMMANDS
#================================================================

set -e

echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID started on $(hostname) at $(date) ---"

# --- 1. Set up environment ---
module load miniforge3
conda activate kraken2.1.3

# --- 2. Source configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/../../config.sh"

# --- 3. Create directories ---
mkdir -p "$KRAKEN2_DIR"
mkdir -p "$LOGS_DIR"

# --- 4. GET SAMPLE NAME FROM THE LIST ---
SAMPLE_NAME=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$SAMPLE_LIST")
echo "--- Processing Sample: $SAMPLE_NAME ---"

# --- 5. DEFINE DIRECTORIES AND FILES ---
INPUT_DIR_SAMPLE="${KNEADDATA_DIR}/${SAMPLE_NAME}"
OUTPUT_DIR_SAMPLE="${KRAKEN2_DIR}/${SAMPLE_NAME}"

# Kraken2 takes Kneaddata output (uncompressed)
# Note: Kneaddata output naming follows the input R1 filename pattern
INPUT_R1="${INPUT_DIR_SAMPLE}/${SAMPLE_NAME}_1_val_1_kneaddata_paired_1.fastq"
INPUT_R2="${INPUT_DIR_SAMPLE}/${SAMPLE_NAME}_1_val_1_kneaddata_paired_2.fastq"

# Expected Kraken2 output files
OUTPUT_REPORT="${OUTPUT_DIR_SAMPLE}/${SAMPLE_NAME}_kraken_report.txt"
OUTPUT_FILE="${OUTPUT_DIR_SAMPLE}/${SAMPLE_NAME}_kraken_output.txt"

# --- 6. AUTO-RESUME CHECK ---
if [[ -f "$OUTPUT_REPORT" && -f "$OUTPUT_FILE" && -s "$OUTPUT_REPORT" && -s "$OUTPUT_FILE" ]]; then
    echo ">>> Sample $SAMPLE_NAME is already processed. Kraken2 output found. Skipping."
    echo "---------------------------------"
    exit 0
fi

# --- 7. INPUT VALIDATION ---
if [[ ! -f "$INPUT_R1" || ! -f "$INPUT_R2" ]]; then
    echo "ERROR: Missing input FASTQ files for sample $SAMPLE_NAME:"
    echo "  R1: $INPUT_R1"
    echo "  R2: $INPUT_R2"
    exit 1
fi

# --- 8. CREATE OUTPUT DIRECTORY ---
mkdir -p "$OUTPUT_DIR_SAMPLE"

echo "Input files:"
echo "  R1: $INPUT_R1"
echo "  R2: $INPUT_R2"
echo "Output directory: $OUTPUT_DIR_SAMPLE"
echo "Kraken2 database: $KRAKEN2_DB"

# --- 9. RUN KRAKEN2 ---
echo "Running Kraken2 on $SAMPLE_NAME..."
kraken2 \
    --db "$KRAKEN2_DB" \
    --paired "$INPUT_R1" "$INPUT_R2" \
    --threads $SLURM_CPUS_PER_TASK \
    --report "$OUTPUT_REPORT" \
    --output "$OUTPUT_FILE" \
    --use-names

# --- 10. VERIFY OUTPUT ---
if [[ -f "$OUTPUT_REPORT" && -f "$OUTPUT_FILE" ]]; then
    echo ">>> Successfully completed Kraken2 for $SAMPLE_NAME"
    echo "Output files:"
    echo "  Report: $OUTPUT_REPORT"
    echo "  Output: $OUTPUT_FILE"
    # Show file sizes for verification
    ls -lh "$OUTPUT_REPORT" "$OUTPUT_FILE"

    # Show top taxa classification
    echo ""
    echo "Top taxonomic classifications:"
    head -n 10 "$OUTPUT_REPORT"
else
    echo ">>> ERROR: Kraken2 failed for $SAMPLE_NAME"
    echo "Expected output files not found:"
    echo "  Report: $OUTPUT_REPORT"
    echo "  Output: $OUTPUT_FILE"
    echo "Files in output directory:"
    ls -la "$OUTPUT_DIR_SAMPLE"
    exit 1
fi

echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID finished at $(date) ---"
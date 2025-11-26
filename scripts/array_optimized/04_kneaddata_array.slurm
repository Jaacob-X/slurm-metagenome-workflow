#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - KNEADDATA ARRAY PROCESSING
#================================================================
# NOTE: SBATCH directives use default values. Adjust these directly or use
# sbatch command-line overrides (e.g., sbatch --cpus-per-task=24 script.slurm)
#SBATCH --job-name=kneaddata_array
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=12:00:00

# --- JOB ARRAY DIRECTIVES ---
# IMPORTANT: Update --array parameter based on your sample count before submission
# Example: --array=1-74%6 for 74 samples with max 6 concurrent jobs
#SBATCH --array=1-2%6
#SBATCH --output=logs/kneaddata_%A_%a.out
#SBATCH --error=logs/kneaddata_%A_%a.err

#================================================================
# SCRIPT COMMANDS
#================================================================

set -e

echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID started on $(hostname) at $(date) ---"

# --- 1. Set up environment ---
module load miniforge3
conda activate kneaddata

# --- 2. Source configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/../../config.sh"

# --- 3. Create directories ---
mkdir -p "$KNEADDATA_DIR"
mkdir -p "$LOGS_DIR"

# --- 4. GET SAMPLE NAME FROM THE LIST ---
SAMPLE_NAME=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$SAMPLE_LIST")
echo "--- Processing Sample: $SAMPLE_NAME ---"

# --- 5. DEFINE DIRECTORIES AND FILES ---
INPUT_DIR_SAMPLE="${TRIMMED_DIR}/${SAMPLE_NAME}"
OUTPUT_DIR_SAMPLE="${KNEADDATA_DIR}/${SAMPLE_NAME}"

# Kneaddata takes Trim Galore compressed output
INPUT_R1="${INPUT_DIR_SAMPLE}/${SAMPLE_NAME}_1_val_1.fq.gz"
INPUT_R2="${INPUT_DIR_SAMPLE}/${SAMPLE_NAME}_2_val_2.fq.gz"

# Expected Kneaddata output files
# Note: Kneaddata names output based on input R1 filename (e.g., sample_1_val_1_kneaddata_paired_1.fastq)
OUTPUT_R1="${OUTPUT_DIR_SAMPLE}/${SAMPLE_NAME}_1_val_1_kneaddata_paired_1.fastq"
OUTPUT_R2="${OUTPUT_DIR_SAMPLE}/${SAMPLE_NAME}_1_val_1_kneaddata_paired_2.fastq"

# --- 6. AUTO-RESUME CHECK ---
if [[ -f "$OUTPUT_R1" && -f "$OUTPUT_R2" && -s "$OUTPUT_R1" && -s "$OUTPUT_R2" ]]; then
    echo ">>> Sample $SAMPLE_NAME is already processed. Kneaddata output found. Skipping."
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
echo "Reference database: $KNEADDATA_DB"

# --- 9. RUN KNEADDATA ---
echo "Running Kneaddata on $SAMPLE_NAME..."
kneaddata \
    --input1 "$INPUT_R1" \
    --input2 "$INPUT_R2" \
    --reference-db "$KNEADDATA_DB" \
    --output "$OUTPUT_DIR_SAMPLE" \
    --threads $SLURM_CPUS_PER_TASK \
    --trimmomatic "$TRIMMOMATIC_PATH" \
    --trimmomatic-options "HEADCROP:15 SLIDINGWINDOW:4:15 MINLEN:50"

# --- 10. VERIFY OUTPUT ---
if [[ -f "$OUTPUT_R1" && -f "$OUTPUT_R2" ]]; then
    echo ">>> Successfully completed Kneaddata for $SAMPLE_NAME"
    echo "Output files:"
    echo "  R1: $OUTPUT_R1"
    echo "  R2: $OUTPUT_R2"
    # Show file sizes for verification
    ls -lh "$OUTPUT_R1" "$OUTPUT_R2"
else
    echo ">>> ERROR: Kneaddata failed for $SAMPLE_NAME"
    echo "Expected output files not found:"
    echo "  R1: $OUTPUT_R1"
    echo "  R2: $OUTPUT_R2"
    echo "Files in output directory:"
    ls -la "$OUTPUT_DIR_SAMPLE"
    exit 1
fi

echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID finished at $(date) ---"
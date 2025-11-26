#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - FASTQC ARRAY PROCESSING
#================================================================
# NOTE: SBATCH directives use default values. Adjust these directly or use
# sbatch command-line overrides (e.g., sbatch --cpus-per-task=8 script.slurm)
#SBATCH --job-name=fastqc_array
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=2:00:00

# --- JOB ARRAY DIRECTIVES ---
# IMPORTANT: Update --array parameter based on your sample count before submission
# Example: --array=1-74%20 for 74 samples with max 20 concurrent jobs
#SBATCH --array=1-2%20
#SBATCH --output=logs/fastqc_%A_%a.out
#SBATCH --error=logs/fastqc_%A_%a.err

#================================================================
# SCRIPT COMMANDS
#================================================================

set -e

echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID started on $(hostname) at $(date) ---"

# --- 1. Set up environment ---
module load fastqc/0.12.1

# --- 2. Source configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/../../config.sh"

# --- 3. Create directories ---
mkdir -p "$FASTQC_DIR"
mkdir -p "$LOGS_DIR"

# --- 4. GET SAMPLE NAME FROM THE LIST ---
# This line reads the sample_list.txt file and picks the line number
# that corresponds to the job array's task ID.
SAMPLE_NAME=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$SAMPLE_LIST")
echo "--- Processing Sample: $SAMPLE_NAME ---"

# --- 5. DEFINE INPUT FILES ---
INPUT_R1="${RAW_DATA_DIR}/${SAMPLE_NAME}_1.fastq.gz"
INPUT_R2="${RAW_DATA_DIR}/${SAMPLE_NAME}_2.fastq.gz"

# --- 6. AUTO-RESUME CHECK ---
# Check if FastQC output already exists for this sample
OUTPUT_DIR_SAMPLE="${FASTQC_DIR}/${SAMPLE_NAME}"
OUTPUT_R1="${OUTPUT_DIR_SAMPLE}/${SAMPLE_NAME}_1_fastqc.html"
OUTPUT_R2="${OUTPUT_DIR_SAMPLE}/${SAMPLE_NAME}_2_fastqc.html"

if [[ -f "$OUTPUT_R1" && -f "$OUTPUT_R2" ]]; then
    echo ">>> Sample $SAMPLE_NAME is already processed. FastQC files found. Skipping."
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

# --- 9. RUN FASTQC ---
echo "Running FastQC on $SAMPLE_NAME..."
fastqc -o "$OUTPUT_DIR_SAMPLE" \
    "$INPUT_R1" "$INPUT_R2"

# --- 10. VERIFY OUTPUT ---
if [[ -f "$OUTPUT_R1" && -f "$OUTPUT_R2" ]]; then
    echo ">>> Successfully completed FastQC for $SAMPLE_NAME"
else
    echo ">>> ERROR: FastQC failed for $SAMPLE_NAME"
    exit 1
fi

echo "--- Job $SLURM_ARRAY_JOB_ID, Task $SLURM_ARRAY_TASK_ID finished at $(date) ---"
#!/bin/bash

#================================================================
# SLURM BATCH JOB SCRIPT - KRAKEN2 SINGLE JOB (ALL SAMPLES)
#================================================================
# NOTE: SBATCH directives use default values. Adjust these directly or use
# sbatch command-line overrides (e.g., sbatch --mem=256G script.slurm)
#SBATCH --job-name=kraken2_single
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=128G
#SBATCH --time=120:00:00
#SBATCH --output=logs/kraken2_single_%j.out
#SBATCH --error=logs/kraken2_single_%j.err

# --- Fail the script if any command fails
set -e

#================================================================
# ENVIRONMENT SETUP
#================================================================
# Activate your Conda environment that contains Kraken2
echo "--- Activating Conda environment ---"
module load miniforge3
# !!! IMPORTANT: Replace 'kraken2_env' if your environment has a different name !!!
conda activate kraken2.1.3
# Verify that the kraken2 command is available
command -v kraken2

#================================================================
# SCRIPT COMMANDS
#================================================================

echo "--- Job started on $(hostname) at $(date) ---"

# --- 1. Source configuration ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/../../config.sh"

# --- 2. DEFINE DIRECTORIES ---
# This is the output directory from your Kneaddata script
INPUT_DIR="$KNEADDATA_DIR"
# This will be the final output directory for the Kraken2 classification results
OUTPUT_BASE_DIR="$KRAKEN2_DIR"

# Create the base output directory if it doesn't exist
mkdir -p "$OUTPUT_BASE_DIR"

echo "Input directory: $INPUT_DIR"
echo "Output directory: $OUTPUT_BASE_DIR"
echo "Kraken2 Database: $KRAKEN2_DB"

# Check if the Kraken2 database path has been set
if [ "$KRAKEN2_DB" == "/path/to/your/kraken2_database" ]; then
    echo "FATAL ERROR: You have not set the KRAKEN_DB variable in the configuration."
    echo "Please edit the config.sh to provide the correct path to your Kraken2 database."
    exit 1
fi

# --- 3. PROCESS EACH SAMPLE ---
processed_count=0
skipped_count=0

for SAMPLE_DIR in "$INPUT_DIR"/*; do
    if [ -d "$SAMPLE_DIR" ]; then
        SAMPLE_NAME=$(basename "$SAMPLE_DIR")

        # Define the output directory and files for this sample
        OUTPUT_DIR="$OUTPUT_BASE_DIR/$SAMPLE_NAME"
        OUTPUT_FILE="$OUTPUT_DIR/${SAMPLE_NAME}_kraken_output.txt"
        REPORT_FILE="$OUTPUT_DIR/${SAMPLE_NAME}_kraken_report.txt"

        # --- AUTO-RESUME CHECK ---
        # If the final report file exists and is not empty, skip this sample
        if [[ -f "$REPORT_FILE" && -s "$REPORT_FILE" && -f "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
            echo ">>> Sample $SAMPLE_NAME is already processed. Report file found. Skipping."
            echo "---------------------------------"
            ((skipped_count++))
            continue
        fi
        # --- END OF CHECK ---

        echo ">>> Processing sample: $SAMPLE_NAME"

        # Define the final, clean paired-end FASTQ files from Kneaddata
        # The filenames are based on the R1 input to Kneaddata
        INPUT_R1="$SAMPLE_DIR/${SAMPLE_NAME}_1_val_1_kneaddata_paired_1.fastq"
        INPUT_R2="$SAMPLE_DIR/${SAMPLE_NAME}_1_val_1_kneaddata_paired_2.fastq"

        # Sanity check to ensure both input files exist
        if [[ ! -f "$INPUT_R1" || ! -f "$INPUT_R2" ]]; then
            echo "ERROR: Missing one or both Kneaddata output FASTQ files for sample $SAMPLE_NAME. Skipping."
            echo "Looked for: $INPUT_R1 and $INPUT_R2"
            continue
        fi

        # Create the output directory for the current sample
        mkdir -p "$OUTPUT_DIR"

        # Run Kraken2, keeping all original parameters
        kraken2 \
            --db "$KRAKEN2_DB" \
            --threads $SLURM_CPUS_PER_TASK \
            --use-names \
            --output "$OUTPUT_FILE" \
            --report "$REPORT_FILE" \
            --paired "$INPUT_R1" "$INPUT_R2"

        # Verify output files were created
        if [[ -f "$REPORT_FILE" && -s "$REPORT_FILE" && -f "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
            echo ">>> Kraken2 completed for sample: $SAMPLE_NAME. Results saved to $OUTPUT_DIR."
            echo "Output files:"
            echo "  Report: $REPORT_FILE"
            echo "  Output: $OUTPUT_FILE"
            # Show file sizes for verification
            ls -lh "$REPORT_FILE" "$OUTPUT_FILE"

            # Show top taxa classification
            echo ""
            echo "Top taxonomic classifications:"
            head -n 10 "$REPORT_FILE"
            ((processed_count++))
        else
            echo ">>> ERROR: Kraken2 failed for sample: $SAMPLE_NAME"
            echo "Expected output files not found:"
            echo "  Report: $REPORT_FILE"
            echo "  Output: $OUTPUT_FILE"
            echo "Files in output directory:"
            ls -la "$OUTPUT_DIR"
            exit 1
        fi

        echo "---------------------------------"
    fi
done

echo "--- All samples processed successfully at $(date) ---"
echo "--- Processed samples: $processed_count ---"
echo "--- Skipped samples: $skipped_count ---"
#!/bin/bash

#================================================================
# METAGENOME PIPELINE MASTER SCRIPT
#================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[ℹ]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 --step STEP [OPTIONS]

Metagenome Pipeline Runner - Executes metagenome analysis steps using SLURM array jobs.

OPTIONS:
    --step STEP              Run specific step (REQUIRED, see STEPS below)
    --script-version VER     Use 'original' or 'array' scripts (default: array)
    --dry-run               Show what would be done without executing
    --resume                Skip already completed steps
    --validate-config       Validate configuration only
    --help                  Show this help message

STEPS (run in this order):
    download                Download raw reads (sequential)
    fastqc                  Quality control assessment
    trimgalore              Read trimming and adapter removal
    kneaddata               Host genome removal
    kraken2                 Taxonomic classification
    humann3                 Functional profiling

EXAMPLES:
    $0 --step download                  # Run download step
    $0 --step fastqc --dry-run          # Preview fastqc submission
    $0 --step trimgalore --resume       # Run trimgalore, skip completed
    $0 --step fastqc --script-version original  # Use single-job scripts
    $0 --validate-config                # Check configuration

NOTES:
    - Requires SLURM scheduler
    - Configuration in config.sh
    - Run steps sequentially; wait for each to complete before the next
    - Array scripts provide 4-20x speedup vs single-job scripts
    - Download step is always sequential (network protection)

EOF
}

# Default values
SCRIPT_VERSION="array"
STEP=""
DRY_RUN=false
RESUME=false
VALIDATE_CONFIG=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --step)
            STEP="$2"
            shift 2
            ;;
        --script-version)
            SCRIPT_VERSION="$2"
            if [[ "$SCRIPT_VERSION" != "original" && "$SCRIPT_VERSION" != "array" ]]; then
                print_error "Invalid script version: $SCRIPT_VERSION. Use 'original' or 'array'"
                exit 1
            fi
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --resume)
            RESUME=true
            shift
            ;;
        --validate-config)
            VALIDATE_CONFIG=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Source configuration
if [[ ! -f "${SCRIPT_DIR}/config.sh" ]]; then
    print_error "Configuration file not found: ${SCRIPT_DIR}/config.sh"
    exit 1
fi

source "${SCRIPT_DIR}/config.sh"

# Validate configuration
if [[ "$VALIDATE_CONFIG" == "true" ]]; then
    print_info "Validating configuration..."
    validate_config
    if [[ $? -eq 0 ]]; then
        print_status "Configuration validation passed"
    else
        print_error "Configuration validation failed"
        exit 1
    fi
    exit 0
fi

# Create directories if needed
if [[ "$CREATE_DIRS" == "true" ]]; then
    create_directories
fi

# Define script paths based on version
if [[ "$SCRIPT_VERSION" == "array" ]]; then
    SCRIPT_BASE_DIR="${SCRIPT_DIR}/scripts/array_optimized"
else
    # "original" maps to single_job scripts
    SCRIPT_BASE_DIR="${SCRIPT_DIR}/scripts/single_job"
fi

# Define available steps based on script version
declare -A STEPS
if [[ "$SCRIPT_VERSION" == "array" ]]; then
    STEPS[download]="01_download_fixed.slurm"
    STEPS[fastqc]="02_fastqc_array.slurm"
    STEPS[trimgalore]="03_trimgalore_array.slurm"
    STEPS[kneaddata]="04_kneaddata_array.slurm"
    STEPS[kraken2]="05_kraken2_array.slurm"
    STEPS[humann3]="06_humann3_array.slurm"
else
    # Single job script names (note: download is still in array_optimized)
    STEPS[download]="../array_optimized/01_download_fixed.slurm"
    STEPS[fastqc]="02_fastqc.slurm"
    STEPS[trimgalore]="03_trimgalore.slurm"
    STEPS[kneaddata]="04_kneaddata.slurm"
    STEPS[kraken2]="05_kraken2.slurm"
    STEPS[humann3]="06_humann3.slurm"
fi

# Define step dependencies
declare -A DEPENDENCIES
DEPENDENCIES[fastqc]="download"
DEPENDENCIES[trimgalore]="download fastqc"
DEPENDENCIES[kneaddata]="trimgalore"
DEPENDENCIES[kraken2]="kneaddata"
DEPENDENCIES[humann3]="kneaddata"

# Function to check if step is completed
is_step_completed() {
    local step=$1
    local sample_count=0
    local completed_count=0

    case $step in
        "download")
            for srr in $(cat "$SAMPLE_LIST"); do
                ((sample_count++))
                if [[ -f "${RAW_DATA_DIR}/${srr}_1.fastq.gz" && -f "${RAW_DATA_DIR}/${srr}_2.fastq.gz" ]]; then
                    ((completed_count++))
                fi
            done
            ;;
        "fastqc")
            for srr in $(cat "$SAMPLE_LIST"); do
                ((sample_count++))
                if [[ -f "${FASTQC_DIR}/${srr}/${srr}_1_fastqc.html" && -f "${FASTQC_DIR}/${srr}/${srr}_2_fastqc.html" ]]; then
                    ((completed_count++))
                fi
            done
            ;;
        "trimgalore")
            for srr in $(cat "$SAMPLE_LIST"); do
                ((sample_count++))
                if [[ -f "${TRIMMED_DIR}/${srr}/${srr}_1_val_1.fq.gz" && -f "${TRIMMED_DIR}/${srr}/${srr}_2_val_2.fq.gz" ]]; then
                    ((completed_count++))
                fi
            done
            ;;
        "kneaddata")
            for srr in $(cat "$SAMPLE_LIST"); do
                ((sample_count++))
                # Kneaddata output filenames are based on input R1 name (sample_1_val_1_kneaddata_paired_1.fastq)
                if [[ -f "${KNEADDATA_DIR}/${srr}/${srr}_1_val_1_kneaddata_paired_1.fastq" && -f "${KNEADDATA_DIR}/${srr}/${srr}_1_val_1_kneaddata_paired_2.fastq" ]]; then
                    ((completed_count++))
                fi
            done
            ;;
        "kraken2")
            for srr in $(cat "$SAMPLE_LIST"); do
                ((sample_count++))
                if [[ -f "${KRAKEN2_DIR}/${srr}/${srr}_kraken_report.txt" && -f "${KRAKEN2_DIR}/${srr}/${srr}_kraken_output.txt" ]]; then
                    ((completed_count++))
                fi
            done
            ;;
        "humann3")
            for srr in $(cat "$SAMPLE_LIST"); do
                ((sample_count++))
                if [[ -f "${HUMANN3_DIR}/${srr}/${srr}_concatenated_genefamilies.tsv" ]]; then
                    ((completed_count++))
                fi
            done
            ;;
        *)
            return 1
            ;;
    esac

    if [[ $completed_count -eq $sample_count && $sample_count -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Function to build sbatch parameters for a step
get_sbatch_params() {
    local step=$1
    local params=""

    # Common parameters
    [[ -n "$SLURM_PARTITION" ]] && params+=" --partition=$SLURM_PARTITION"
    [[ -n "$SLURM_ACCOUNT" ]] && params+=" --account=$SLURM_ACCOUNT"
    [[ -n "$LOGS_DIR" ]] && params+=" --output=$LOGS_DIR/${step}_%A_%a.out --error=$LOGS_DIR/${step}_%A_%a.err"

    # Step-specific parameters
    case $step in
        "download")
            [[ -n "$DOWNLOAD_CPUS" ]] && params+=" --cpus-per-task=$DOWNLOAD_CPUS"
            [[ -n "$DOWNLOAD_MEM" ]] && params+=" --mem=$DOWNLOAD_MEM"
            [[ -n "$DOWNLOAD_TIME" ]] && params+=" --time=$DOWNLOAD_TIME"
            ;;
        "fastqc")
            [[ -n "$FASTQC_CPUS" ]] && params+=" --cpus-per-task=$FASTQC_CPUS"
            [[ -n "$FASTQC_MEM" ]] && params+=" --mem=$FASTQC_MEM"
            if [[ "$SCRIPT_VERSION" == "array" ]]; then
                [[ -n "$FASTQC_TIME" ]] && params+=" --time=$FASTQC_TIME"
                params+=" --array=1-${NUM_SAMPLES}%${MAX_CONCURRENT_FASTQC:-20}"
            else
                [[ -n "$FASTQC_SINGLE_TIME" ]] && params+=" --time=$FASTQC_SINGLE_TIME"
            fi
            ;;
        "trimgalore")
            [[ -n "$TRIMGALORE_CPUS" ]] && params+=" --cpus-per-task=$TRIMGALORE_CPUS"
            [[ -n "$TRIMGALORE_MEM" ]] && params+=" --mem=$TRIMGALORE_MEM"
            if [[ "$SCRIPT_VERSION" == "array" ]]; then
                [[ -n "$TRIMGALORE_TIME" ]] && params+=" --time=$TRIMGALORE_TIME"
                params+=" --array=1-${NUM_SAMPLES}%${MAX_CONCURRENT_TRIMGALORE:-8}"
            else
                [[ -n "$TRIMGALORE_SINGLE_TIME" ]] && params+=" --time=$TRIMGALORE_SINGLE_TIME"
            fi
            ;;
        "kneaddata")
            [[ -n "$KNEADDATA_CPUS" ]] && params+=" --cpus-per-task=$KNEADDATA_CPUS"
            [[ -n "$KNEADDATA_MEM" ]] && params+=" --mem=$KNEADDATA_MEM"
            if [[ "$SCRIPT_VERSION" == "array" ]]; then
                [[ -n "$KNEADDATA_TIME" ]] && params+=" --time=$KNEADDATA_TIME"
                params+=" --array=1-${NUM_SAMPLES}%${MAX_CONCURRENT_KNEADDATA:-6}"
            else
                [[ -n "$KNEADDATA_SINGLE_TIME" ]] && params+=" --time=$KNEADDATA_SINGLE_TIME"
            fi
            ;;
        "kraken2")
            [[ -n "$KRAKEN2_CPUS" ]] && params+=" --cpus-per-task=$KRAKEN2_CPUS"
            [[ -n "$KRAKEN2_MEM" ]] && params+=" --mem=$KRAKEN2_MEM"
            if [[ "$SCRIPT_VERSION" == "array" ]]; then
                [[ -n "$KRAKEN2_TIME" ]] && params+=" --time=$KRAKEN2_TIME"
                params+=" --array=1-${NUM_SAMPLES}%${MAX_CONCURRENT_KRAKEN2:-4}"
            else
                [[ -n "$KRAKEN2_SINGLE_TIME" ]] && params+=" --time=$KRAKEN2_SINGLE_TIME"
            fi
            ;;
        "humann3")
            [[ -n "$HUMANN3_CPUS" ]] && params+=" --cpus-per-task=$HUMANN3_CPUS"
            [[ -n "$HUMANN3_MEM" ]] && params+=" --mem=$HUMANN3_MEM"
            if [[ "$SCRIPT_VERSION" == "array" ]]; then
                [[ -n "$HUMANN3_TIME" ]] && params+=" --time=$HUMANN3_TIME"
                params+=" --array=1-${NUM_SAMPLES}%${MAX_CONCURRENT_HUMANN3:-20}"
            else
                [[ -n "$HUMANN3_SINGLE_TIME" ]] && params+=" --time=$HUMANN3_SINGLE_TIME"
            fi
            ;;
    esac

    echo "$params"
}

# Function to submit SLURM job
submit_job() {
    local step=$1
    local script_name=${STEPS[$step]}
    local script_path="${SCRIPT_BASE_DIR}/${script_name}"

    if [[ ! -f "$script_path" ]]; then
        print_error "Script not found: $script_path"
        return 1
    fi

    if [[ "$RESUME" == "true" ]] && is_step_completed "$step"; then
        print_info "Step '$step' already completed, skipping"
        return 0
    fi

    # Build sbatch parameters from configuration
    local sbatch_params
    sbatch_params=$(get_sbatch_params "$step")

    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would submit: sbatch$sbatch_params $script_path"
        return 0
    fi

    print_info "Submitting step '$step': sbatch$sbatch_params $script_path"

    local job_id
    job_id=$(sbatch $sbatch_params "$script_path" | awk '{print $4}')

    if [[ -n "$job_id" ]]; then
        print_status "Step '$step' submitted (Job ID: $job_id)"
        echo "$job_id"
    else
        print_error "Failed to submit step '$step'"
        return 1
    fi
}

# Function to check job dependencies
check_dependencies() {
    local step=$1
    local deps=${DEPENDENCIES[$step]}

    if [[ -z "$deps" ]]; then
        return 0
    fi

    for dep in $deps; do
        if [[ "$RESUME" == "true" ]] && is_step_completed "$dep"; then
            print_info "Dependency '$dep' already completed"
        elif ! is_step_completed "$dep"; then
            print_error "Dependency '$dep' not completed. Please run step '$dep' first."
            return 1
        fi
    done

    return 0
}

# Main execution logic
print_info "Metagenome Pipeline Runner"
print_info "Script version: $SCRIPT_VERSION"
print_info "Step: $STEP"
echo

# Validate step
if [[ -z "$STEP" ]]; then
    print_error "No step specified. Use --step STEP to specify a step."
    echo "Available steps: ${!STEPS[*]}"
    exit 1
fi

if [[ -z "${STEPS[$STEP]}" ]]; then
    print_error "Unknown step: $STEP"
    echo "Available steps: ${!STEPS[*]}"
    exit 1
fi

# Check sample list
if [[ ! -f "$SAMPLE_LIST" ]]; then
    print_error "Sample list not found: $SAMPLE_LIST"
    exit 1
fi

# Count samples
SAMPLE_COUNT=$(wc -l < "$SAMPLE_LIST")
print_info "Found $SAMPLE_COUNT samples in $SAMPLE_LIST"

# Execute step
echo
print_info "=== Step: $STEP ==="

# Check dependencies
if ! check_dependencies "$STEP"; then
    exit 1
fi

# Submit job
submit_job "$STEP"

echo
print_info "Pipeline runner completed!"
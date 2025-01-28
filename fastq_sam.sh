#!/bin/bash
set -e

#==============================================================================
# Title: FASTQ to BAM Processing Pipeline
# Description: Processes FASTQ files to BAM files across multiple directories
#
# Author: Gavin Mason
# Email: gavin@rawcsav.com
# Version: 1.0.2
# Created: With love for Anson :)
#
# Dependencies:
#   - minimap2
#   - samtools
#==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )

declare -a TEMP_DIRS=()
declare -a DECOMPRESSED_FILES=()

show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}


progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "\rProgress: ["
    printf "%${completed}s" | tr ' ' '='
    printf "%${remaining}s" | tr ' ' ' '
    printf "] %d%%" "$percentage"
}


print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}


print_success() {
    echo -e "${GREEN}✔ $1${NC}"
}


print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}


print_error() {
    echo -e "${RED}✘ $1${NC}"
}

cleanup() {
    if [ "$RUNNING_USAGE" = true ]; then
        return 0
    fi

    print_header "Cleaning up temporary files"
    
        if [ ${#DECOMPRESSED_FILES[@]} -gt 0 ]; then
        print_warning "Removing decompressed FASTQ files..."
        for file in "${DECOMPRESSED_FILES[@]}"; do
            if [ -f "$file" ]; then
                rm "$file"
            fi
        done
    else
        print_success "No decompressed FASTQ files to remove."
    fi

    
    if [ ${#TEMP_DIRS[@]} -gt 0 ]; then
        print_warning "Removing temporary directories..."
        for dir in "${TEMP_DIRS[@]}"; do
            if [ -d "$dir" ]; then
                rm -rf "$dir"
            fi
        done
    else
        print_success "No temporary directories to remove."
    fi

    print_success "Cleanup complete!"
}

trap cleanup EXIT


check_dependencies() {
    print_header "Checking dependencies"
    local missing_deps=0

    command -v minimap2 >/dev/null 2>&1 || { print_error "minimap2 is required but not installed."; missing_deps=1; }
    command -v samtools >/dev/null 2>&1 || { print_error "samtools is required but not installed."; missing_deps=1; }

    if [ $missing_deps -eq 1 ]; then
        print_error "Please install missing dependencies and try again."
        exit 1
    fi
    print_success "All dependencies found!"
}

show_usage() {
    RUNNING_USAGE=true
    echo -e "${BLUE}FASTQ to BAM Processing Pipeline${NC}\n"
    echo -e "Usage: $0 [OPTIONS]"
    echo -e "Options:"
    echo -e "  -b, --base-dir DIR     Specify IGVTesting directory (default: ./IGVTesting)"
    echo -e "  -s, --subfolder DIR    Process specific project directory"
    echo -e "  -a, --all             Process all project directories"
    echo -e "  -t, --threads NUM      Number of threads to use (default: 8)"
    echo -e "  -r, --reference FILE   Override default reference path"
    echo -e "  -h, --help            Show this help message\n"
    echo -e "${YELLOW}Note: This script requires minimap2 and samtools to be installed.${NC}"
}



process_barcode() {
    local barcode_dir=$1
    local project_dir=$2
    local reference=$3
    local threads=$4

    print_header "Processing barcode directory: $barcode_dir in project: $(basename "$project_dir")"

    
    local temp_sam_dir="$project_dir/data/temp_sam"
    local temp_bam_dir="$project_dir/data/temp_bam"
    local final_bam_dir="$project_dir/data/final_bam"

    
    mkdir -p "$temp_sam_dir" "$temp_bam_dir" "$final_bam_dir"
    TEMP_DIRS+=("$temp_sam_dir" "$temp_bam_dir")

    
    print_header "Decompressing FASTQ files..."
    for compressed in "$barcode_dir"/*.{gz,zip}; do
        [[ -e "$compressed" ]] || continue
        if [[ "$compressed" == *.gz ]]; then
            output_file="${compressed%.gz}"
            gunzip -k "$compressed"
            DECOMPRESSED_FILES+=("$output_file")
            print_success "Decompressed: $output_file"
        elif [[ "$compressed" == *.zip ]]; then
            unzip -j -d "$(dirname "$compressed")" "$compressed"
            while IFS= read -r -d '' file; do
                DECOMPRESSED_FILES+=("$file")
                print_success "Decompressed: $file"
            done < <(find "$(dirname "$compressed")" -maxdepth 1 -type f \( -name "*.fastq" -o -name "*.fq" \) -print0)
        fi
    done

    
    print_header "Processing FASTQ files with minimap2..."
    local fastq_count=0
    local total_fastqs=$(find "$barcode_dir" -maxdepth 1 -type f \( -name "*.fastq" -o -name "*.fq" \) | wc -l)
    
    for fastq in "$barcode_dir"/*.{fastq,fq}; do
        [[ -e "$fastq" ]] || continue
        ((fastq_count++))
        filename=$(basename "$fastq")
        base="${filename%.*}"
        output_sam="$temp_sam_dir/${base}.sam"
        minimap2 -t "$threads" -a -x sr "$reference" "$fastq" -o "$output_sam" 2>/dev/null
        print_success "Done"
        progress_bar $fastq_count $total_fastqs
    done
    echo

    
    print_header "Converting SAM to BAM with additional processing..."
    local sam_count=0
    local total_sams=$(find "$temp_sam_dir" -name "*.sam" | wc -l)
    
    for sam in "$temp_sam_dir"/*.sam; do
        [[ -e "$sam" ]] || continue
        ((sam_count++))
        basename=$(basename "$sam" .sam)
        output_bam="$temp_bam_dir/${basename}.bam"
        echo -n "Processing ${basename}... "
        samtools fixmate -m -u "$sam" - 2>/dev/null | \
        samtools sort -u -@"$threads" - 2>/dev/null | \
        samtools markdup -@"$threads" - - 2>/dev/null | \
        samtools view -b -o "$output_bam" - 2>/dev/null
        samtools index "$output_bam" 2>/dev/null
        print_success "Done"
        progress_bar $sam_count $total_sams
    done
    echo

    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local final_bam="$final_bam_dir/merged_${timestamp}.bam"

    
    print_header "Merging BAM files..."
    echo -n "Creating merged BAM file... "
    samtools merge -@"$threads" "$final_bam" "$temp_bam_dir"/*.bam 2>/dev/null
    samtools index "$final_bam" 2>/dev/null
    print_success "Done"
    echo "Final BAM file: $final_bam"

    print_success "Completed processing barcode directory: $barcode_dir"
}


process_project() {
    local project_dir=$1
    local threads=$2
    local reference=$3

    echo "Processing project directory: $(basename "$project_dir")"

    
    if [ -z "$reference" ]; then
        reference="$project_dir/errorCorrection/reference.fasta"
        echo "Using default reference path: $reference"
    fi

    
    if [ ! -f "$reference" ]; then
        echo "Error: Reference genome file '$reference' does not exist for project $(basename "$project_dir")"
        return 1
    fi

    
    for barcode_dir in "$project_dir/data"/barcode*/; do
        if [ -d "$barcode_dir" ]; then
            process_barcode "$barcode_dir" "$project_dir" "$reference" "$threads"
        fi
    done
}


IGV_DIR="./IGVTesting"
THREADS=8
PROCESS_ALL=false
PROJECT_DIR=""
REFERENCE=""

if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--base-dir)
            IGV_DIR="$2"
            shift 2
            ;;
        -s|--subfolder)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: Missing argument for -s|--subfolder option."
                RUNNING_USAGE=true
                exit 1
            fi
            if [[ "$PROCESS_ALL" == true ]]; then
                echo "Error: Options -s|--subfolder and -a|--all cannot be used together."
                RUNNING_USAGE=true
                exit 1
            fi
            PROJECT_DIR="$2"
            shift 2
            ;;
        -a|--all)
            if [[ -n "$PROJECT_DIR" ]]; then
                echo "Error: Options -s|--subfolder and -a|--all cannot be used together."
                RUNNING_USAGE=true
                exit 1
            fi
            PROCESS_ALL=true
            shift
            ;;
        -t|--threads)
            THREADS="$2"
            shift 2
            ;;
        -r|--reference)
            REFERENCE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

if [[ -z "$PROJECT_DIR" && "$PROCESS_ALL" == false ]]; then
    echo "Error: Either -s|--subfolder or -a|--all must be specified."
    RUNNING_USAGE=true
    exit 1
fi

if [ ! -d "$IGV_DIR" ]; then
    echo "Error: IGVTesting directory '$IGV_DIR' does not exist"
    exit 1
fi

if [ "$PROCESS_ALL" = true ]; then
    echo "Processing all project directories in $IGV_DIR"
    for dir in "$IGV_DIR"/*/; do
        if [ -d "$dir" ]; then
            process_project "$dir" "$THREADS" "$REFERENCE"
        fi
    done
else
    if [ -z "$PROJECT_DIR" ]; then
        echo "Available project directories:"
        ls -d "$IGV_DIR"/*/ 2>/dev/null | while read -r dir; do
            echo "  $(basename "$dir")"
        done
        read -p "Enter the project directory to process: " PROJECT_DIR
    fi

    full_project_path="$IGV_DIR/$PROJECT_DIR"
    if [ ! -d "$full_project_path" ]; then
        echo "Error: Project directory '$PROJECT_DIR' does not exist"
        exit 1
    fi
    process_project "$full_project_path" "$THREADS" "$REFERENCE"
fi

echo "Pipeline completed successfully!"

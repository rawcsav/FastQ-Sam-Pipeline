# FASTQ to BAM Processing Pipeline

## Overview

The FASTQ to BAM Processing Pipeline is a Bash script designed to automate the conversion of FASTQ files to BAM files across multiple directories.

## Requirements

- **minimap2**: A versatile sequence alignment program.
- **samtools**: A suite of programs for interacting with high-throughput sequencing data.

Ensure these dependencies are installed and accessible in your system's PATH.

## Installation

1. Clone the repository or download the script file.
2. Ensure the script has executable permissions:
   ```bash
   chmod +x fastq_sam.sh
   ```

## Usage

Run the script with the desired options:

```bash
./fastq_sam.sh [OPTIONS]
```

### Options

- `-b, --base-dir DIR`: Specify the base directory for IGVTesting (default: `./IGVTesting`).
- `-s, --subfolder DIR`: Process a specific project directory.
- `-a, --all`: Process all project directories.
- `-t, --threads NUM`: Number of threads to use (default: 8).
- `-r, --reference FILE`: Override the default reference path.
- `-h, --help`: Display the help message.

### Examples

- Process a specific subfolder:
  ```bash
  ./fastq_sam.sh -s my_project
  ```

- Process all directories with 16 threads:
  ```bash
  ./fastq_sam.sh -a -t 16
  ```

## Acknowledgments

Created with love for my dearest Anson Siu <3


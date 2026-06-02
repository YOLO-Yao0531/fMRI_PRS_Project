#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-versions}"
mkdir -p "$OUT_DIR"

TOOLS=(
  python
  python3
  pip
  pip3
  conda
  mamba
  plink
  plink2
  R
  PRSice.R
  bcftools
  samtools
  tabix
  bgzip
)

for t in "${TOOLS[@]}"; do
  if command -v "$t" >/dev/null 2>&1; then
    which "$t" >> "$OUT_DIR/software_paths.txt"
  fi
done

check_version() {
  local tool="$1"
  local output_file="$OUT_DIR/software_versions.txt"
  if ! command -v "$tool" >/dev/null 2>&1; then
    return
  fi

  {
    echo "=== $tool ==="
    "$tool" --version 2>/dev/null || "$tool" -V 2>/dev/null || "$tool" version 2>/dev/null || true
    echo
  } >> "$output_file"
}

: > "$OUT_DIR/software_paths.txt"
: > "$OUT_DIR/software_versions.txt"

for t in "${TOOLS[@]}"; do
  check_version "$t"
done

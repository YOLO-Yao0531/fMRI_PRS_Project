#!/usr/bin/env bash
set -euo pipefail

# Restore schizophrenia PRS software environment on a new Linux server.
# This installs software only. It does not download or copy genotype data, GWAS files,
# phenotype files, or LD reference panels.

WORKDIR="${1:-$HOME/bio_software}"
ENV_NAME="${ENV_NAME:-prs_env}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

if ! command -v conda >/dev/null 2>&1; then
  echo "ERROR: conda is not available. Install Miniconda/Mambaforge first, then rerun." >&2
  exit 1
fi

if command -v mamba >/dev/null 2>&1; then
  PM="mamba"
else
  PM="conda"
fi

if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  "$PM" create -y -n "$ENV_NAME" -c conda-forge python=3.10 numpy scipy h5py pandas r-base unzip curl git
fi

# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "$ENV_NAME"
python -m pip install --upgrade pip
python -m pip install numpy scipy h5py

mkdir -p PRSice
if [[ ! -x PRSice/PRSice_linux || ! -f PRSice/PRSice.R ]]; then
  curl -L -o PRSice/PRSice_linux.zip https://github.com/choishingwan/PRSice/releases/latest/download/PRSice_linux.zip
  (cd PRSice && unzip -o PRSice_linux.zip && chmod +x PRSice_linux || true)
fi

if [[ ! -x "$WORKDIR/plink" || -d "$WORKDIR/plink" ]]; then
  tmp_plink_dir="$(mktemp -d)"
  curl -L -o "$tmp_plink_dir/plink.zip" https://s3.amazonaws.com/plink1-assets/plink_linux_x86_64_20231211.zip
  (cd "$tmp_plink_dir" && unzip -o plink.zip && chmod +x plink)
  mv "$tmp_plink_dir/plink" "$WORKDIR/plink"
  rm -rf "$tmp_plink_dir"
fi

mkdir -p "$HOME/software"
if [[ ! -x "$HOME/software/plink2" || -d "$HOME/software/plink2" ]]; then
  tmp_plink2_dir="$(mktemp -d)"
  curl -L -o "$tmp_plink2_dir/plink2.zip" https://s3.amazonaws.com/plink2-assets/plink2_linux_x86_64_20240526.zip
  (cd "$tmp_plink2_dir" && unzip -o plink2.zip && chmod +x plink2)
  mv "$tmp_plink2_dir/plink2" "$HOME/software/plink2"
  rm -rf "$tmp_plink2_dir"
fi

if [[ ! -d PRScs ]]; then
  git clone https://github.com/getian107/PRScs.git PRScs
fi

cat <<PATHMSG

Add these lines to ~/.bashrc if they are not already present:
export PATH="$WORKDIR:$HOME/software:$WORKDIR/PRSice:\$PATH"
export PRSCS_DIR="$WORKDIR/PRScs"

Then test:
  $WORKDIR/plink --version
  $HOME/software/plink2 --version
  Rscript $WORKDIR/PRSice/PRSice.R --help
  python $WORKDIR/PRScs/PRScs.py -h
PATHMSG

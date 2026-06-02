#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${1:-$HOME/bioinfo_tools}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[1/6] Check conda/mamba"
if ! command -v conda >/dev/null 2>&1; then
  echo "Conda not found. Please install Miniconda first: https://docs.conda.io/en/latest/miniconda.html"
  exit 1
fi

if command -v mamba >/dev/null 2>&1; then
  PM="mamba"
else
  PM="conda"
fi

echo "[2/6] Create conda env prs_env"
$PM create -y -n prs_env python=3.10 numpy scipy h5py pip

# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate prs_env

echo "[3/6] Install plink 1.9"
mkdir -p plink && cd plink
curl -L -o plink.zip https://s3.amazonaws.com/plink1-assets/plink_linux_x86_64_20231211.zip
unzip -o plink.zip
chmod +x plink
cd ..

echo "[4/6] Install plink2"
mkdir -p plink2 && cd plink2
curl -L -o plink2.zip https://s3.amazonaws.com/plink2-assets/plink2_linux_x86_64_20240526.zip
unzip -o plink2.zip
chmod +x plink2
cd ..

echo "[5/6] Install PRSice"
mkdir -p PRSice && cd PRSice
curl -L -o PRSice_linux.zip https://github.com/choishingwan/PRSice/releases/latest/download/PRSice_linux.zip
unzip -o PRSice_linux.zip
chmod +x PRSice_linux
cd ..

echo "[6/6] Install PRS-CS and python deps"
git clone https://github.com/getian107/PRScs.git PRScs || true
python -m pip install --upgrade pip
python -m pip install numpy scipy h5py

cat <<'PATHMSG'

Add the following to your ~/.bashrc:
export PATH="$HOME/bioinfo_tools/plink:$HOME/bioinfo_tools/plink2:$HOME/bioinfo_tools/PRSice:$PATH"

Usage examples:
plink --help
plink2 --help
Rscript $HOME/bioinfo_tools/PRSice/PRSice.R --help
python $HOME/bioinfo_tools/PRScs/PRScs.py -h
PATHMSG

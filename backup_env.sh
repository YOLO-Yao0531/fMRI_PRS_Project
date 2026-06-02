#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:-env_backup}"
mkdir -p "$OUTPUT_DIR"/{configs,exports,versions,logs,scripts}

log() { echo "[$(date +'%F %T')] $*"; }

safe_cmd() {
  local outfile="$1"
  shift
  if "$@" >"$outfile" 2>"${outfile}.err"; then
    rm -f "${outfile}.err"
  else
    log "WARN: command failed: $*" | tee -a "$OUTPUT_DIR/logs/warnings.log"
  fi
}

log "Collecting shell configuration"
cp -f ~/.bashrc "$OUTPUT_DIR/configs/bashrc.backup" 2>/dev/null || true
cp -f ~/.bash_profile "$OUTPUT_DIR/configs/bash_profile.backup" 2>/dev/null || true
cp -f ~/.profile "$OUTPUT_DIR/configs/profile.backup" 2>/dev/null || true

log "Collecting PATH and environment variables"
printf '%s\n' "$PATH" | tr ':' '\n' > "$OUTPUT_DIR/configs/path_entries.txt"
printenv | sort > "$OUTPUT_DIR/configs/env_vars_full.txt"

log "Collecting conda/mamba information"
if command -v conda >/dev/null 2>&1; then
  safe_cmd "$OUTPUT_DIR/exports/conda_info.txt" conda info
  safe_cmd "$OUTPUT_DIR/exports/conda_list_global.txt" conda list
  safe_cmd "$OUTPUT_DIR/exports/conda_env_list.txt" conda env list

  while read -r env_name; do
    [[ -z "$env_name" ]] && continue
    safe_cmd "$OUTPUT_DIR/exports/conda_env_${env_name}.yml" conda env export -n "$env_name"
    safe_cmd "$OUTPUT_DIR/exports/conda_explicit_${env_name}.txt" conda list -n "$env_name" --explicit
    safe_cmd "$OUTPUT_DIR/exports/pip_freeze_${env_name}.txt" conda run -n "$env_name" python -m pip freeze
  done < <(conda env list | awk 'NR>2 {print $1}' | sed '/^$/d' | sed '/^#/d')
else
  log "WARN: conda not found" | tee -a "$OUTPUT_DIR/logs/warnings.log"
fi

if command -v mamba >/dev/null 2>&1; then
  safe_cmd "$OUTPUT_DIR/exports/mamba_info.txt" mamba info
fi

log "Collecting software locations and versions"
cat > "$OUTPUT_DIR/scripts/software_probe.sh" <<'PROBE'
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
PROBE

chmod +x "$OUTPUT_DIR/scripts/software_probe.sh"
"$OUTPUT_DIR/scripts/software_probe.sh" "$OUTPUT_DIR/versions"

log "Generating install_local.sh"
cat > "$OUTPUT_DIR/install_local.sh" <<'INSTALL'
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
INSTALL

chmod +x "$OUTPUT_DIR/install_local.sh"

log "Generating .gitignore"
cat > "$OUTPUT_DIR/.gitignore" <<'GITIGNORE'
# Genotype binary files
*.bed
*.bim
*.fam

# Compressed large files
*.gz

# LD reference blocks
ldblk_1kg_eas/

# Raw genomic data (edit this list for your project)
raw_data/
raw_genotype/
input_data/
WGS/
WES/

# Credentials and secrets
*.pem
*.key
*.crt
*.p12
*.token
*token*
*secret*
*password*
.env

# Python / notebook cache
__pycache__/
*.pyc
.ipynb_checkpoints/

# Logs and tmp
*.log
*.tmp
GITIGNORE

log "Generating README.md"
cat > "$OUTPUT_DIR/README.md" <<'README'
# Bioinformatics Environment Backup

This folder stores **reproducible software environment metadata** only (not full system snapshots, and no large dataset files).

## Included
- Shell configs: `.bashrc`, `.bash_profile`, `.profile`
- PATH entries and all environment variables
- Conda/Mamba environment exports (`.yml`, explicit package lists)
- Pip package freeze from each conda env
- Software binary paths and versions
- `install_local.sh` for rebuilding on another Linux machine
- `.gitignore` template for genomic projects

## Quick start (on remote server)
```bash
bash backup_env.sh
# or custom folder
bash backup_env.sh my_env_backup
```

## Rebuild on another Linux machine
1. Install Miniconda (if not installed).
2. Copy this backup folder to local machine.
3. Run:
   ```bash
   cd env_backup
   bash install_local.sh
   ```
4. (Optional) Restore shell config snippets from `configs/` manually.

## GitHub backup steps
```bash
# inside env_backup
cd env_backup
git init
git add .
git commit -m "backup: reproducible bioinformatics environment"
git branch -M main
git remote add origin <YOUR_GITHUB_REPO_URL>
git push -u origin main
```

## Notes
- Before push, review `configs/env_vars_full.txt` and remove sensitive variables if needed.
- This backup intentionally excludes genotype/raw files and secrets.
README

log "Done. Backup directory created: $OUTPUT_DIR"

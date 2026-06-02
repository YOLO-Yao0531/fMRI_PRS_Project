#!/usr/bin/env bash
set -euo pipefail

# One-click backup generator for schizophrenia PRS (PRSice + PRS-CS) analysis environments.
# It records software configuration and path templates only; it never copies genotype,
# GWAS summary statistics, LD reference blocks, or other large/raw data files.

OUTPUT_DIR="${1:-env_backup}"
OUTPUT_PREEXISTED=false
[[ -d "$OUTPUT_DIR" ]] && OUTPUT_PREEXISTED=true

log() { echo "[$(date +'%F %T')] $*"; }

skip_large_or_sensitive_backup_file() {
  local file="$1"
  case "$file" in
    *.bed|*.bim|*.fam|*.pgen|*.pvar|*.psam|*.gz|*.bgz|*.zip|*.tar|*.tar.gz|*.pem|*.key|*.token|*.env) return 0 ;;
    *ldblk_1kg_eas*|*ldblk_1kg_eur*|*ldblk_1kg_afr*|*ldblk_1kg_amr*|*ldblk_1kg_sas*) return 0 ;;
    *GWAS*|*gwas*|*sumstats*|*summary_statistics*|*raw_data*|*raw_genotype*|*genotype*|*phenotype*) return 0 ;;
  esac
  [[ -f "$file" ]] || return 0
  [[ $(wc -c < "$file") -le 10485760 ]] || return 0
  return 1
}

preserve_existing_metadata() {
  local preserve_dir="$OUTPUT_DIR/previous_generated_metadata/$(date +'%Y%m%d_%H%M%S')"
  local root_file src rel dest
  mkdir -p "$preserve_dir"

  for root_file in \
    README.md .gitignore prs_environment_summary.md \
    run_prsice_template.sh run_prscs_template.sh restore_prs_environment.sh install_local.sh; do
    src="$OUTPUT_DIR/$root_file"
    if [[ -f "$src" ]] && ! skip_large_or_sensitive_backup_file "$src"; then
      mkdir -p "$preserve_dir/$(dirname "$root_file")"
      cp -p "$src" "$preserve_dir/$root_file"
    fi
  done

  for src_dir in configs exports versions logs scripts; do
    [[ -d "$OUTPUT_DIR/$src_dir" ]] || continue
    while IFS= read -r -d '' src; do
      rel="${src#$OUTPUT_DIR/}"
      [[ "$rel" == previous_generated_metadata/* ]] && continue
      skip_large_or_sensitive_backup_file "$src" && continue
      dest="$preserve_dir/$rel"
      mkdir -p "$(dirname "$dest")"
      cp -p "$src" "$dest"
    done < <(find "$OUTPUT_DIR/$src_dir" -type f -print0)
  done

  log "Existing env backup metadata preserved under: $preserve_dir"
}

mkdir -p "$OUTPUT_DIR"/{configs,exports,versions,logs,scripts}
if [[ "$OUTPUT_PREEXISTED" == true ]]; then
  preserve_existing_metadata
fi

WARNINGS_FILE="$OUTPUT_DIR/logs/warnings.log"
: > "$WARNINGS_FILE"
warn() { log "WARN: $*" | tee -a "$WARNINGS_FILE"; }

safe_cmd() {
  local outfile="$1"
  shift
  if "$@" >"$outfile" 2>"${outfile}.err"; then
    rm -f "${outfile}.err"
  else
    warn "command failed: $* (see ${outfile}.err)"
  fi
}

first_existing_path() {
  local p
  for p in "$@"; do
    [[ -n "$p" && -e "$p" ]] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

first_existing_dir() {
  local p
  for p in "$@"; do
    [[ -n "$p" && -d "$p" ]] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

command_path_or_empty() {
  local cmd="$1"
  command -v "$cmd" 2>/dev/null || true
}

resolve_executable_or_dir_tool() {
  local tool_name="$1"
  shift
  local candidate
  for candidate in "$@"; do
    [[ -z "$candidate" ]] && continue
    if [[ -x "$candidate" && ! -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [[ -d "$candidate" && -x "$candidate/$tool_name" ]]; then
      printf '%s\n' "$candidate/$tool_name"
      return 0
    fi
  done
  return 1
}

run_version_probe() {
  local label="$1"
  local outfile="$2"
  shift 2
  {
    echo "=== $label ==="
    "$@" 2>&1 || true
    echo
  } >> "$outfile"
}

expand_home_path() {
  local p="$1"
  if [[ "$p" == ~/* ]]; then
    printf '%s/%s\n' "$HOME" "${p#~/}"
  else
    printf '%s\n' "$p"
  fi
}

# User-provided known server paths, plus PATH-based discovery fallbacks.
KNOWN_PRSICE_R="$(expand_home_path "~/bio_software/PRSice/PRSice.R")"
KNOWN_PRSICE_DIR="$(expand_home_path "~/bio_software/PRSice")"
KNOWN_PRSCS_DIR="$(expand_home_path "~/bio_software/PRScs")"
KNOWN_PLINK="$(expand_home_path "~/bio_software/plink")"
KNOWN_PLINK2="$(expand_home_path "~/software/plink2")"

PRSICE_R_PATH="$(first_existing_path "$KNOWN_PRSICE_R" "$(command_path_or_empty PRSice.R)" || true)"
PRSICE_DIR="$(first_existing_dir "$KNOWN_PRSICE_DIR" "${PRSICE_R_PATH%/*}" || true)"
PRSCS_DIR="$(first_existing_dir "$KNOWN_PRSCS_DIR" "$HOME/PRScs" "$HOME/bioinfo_tools/PRScs" || true)"
PRSCS_SCRIPT="$(first_existing_path "$PRSCS_DIR/PRScs.py" "$PRSCS_DIR/PRScs.pyc" || true)"
PLINK_PATH="$(resolve_executable_or_dir_tool plink "$KNOWN_PLINK" "$(command_path_or_empty plink)" || true)"
PLINK2_PATH="$(resolve_executable_or_dir_tool plink2 "$KNOWN_PLINK2" "$(command_path_or_empty plink2)" || true)"

log "Collecting shell configuration"
cp -f ~/.bashrc "$OUTPUT_DIR/configs/bashrc.backup" 2>/dev/null || true
cp -f ~/.bash_profile "$OUTPUT_DIR/configs/bash_profile.backup" 2>/dev/null || true
cp -f ~/.profile "$OUTPUT_DIR/configs/profile.backup" 2>/dev/null || true

log "Collecting PATH and PRS/genetics-related PATH entries"
printf '%s\n' "$PATH" | tr ':' '\n' > "$OUTPUT_DIR/configs/path_entries.txt"
awk 'BEGIN{IGNORECASE=1} /plink|plink2|prs|prscs|prsice|gwas|geno|genetic|bio_software|bcftools|samtools|htslib|tabix|bgzip|ldblk|\/R($|\/)|rscript/ {print}' \
  "$OUTPUT_DIR/configs/path_entries.txt" > "$OUTPUT_DIR/configs/genetics_path_entries.txt" || true

log "Collecting environment variables (review for secrets before GitHub push)"
printenv | sort > "$OUTPUT_DIR/configs/env_vars_full.review_before_push.txt"

log "Collecting conda/mamba information"
if command -v conda >/dev/null 2>&1; then
  safe_cmd "$OUTPUT_DIR/exports/conda_info.txt" conda info
  safe_cmd "$OUTPUT_DIR/exports/conda_list_active.txt" conda list
  safe_cmd "$OUTPUT_DIR/exports/conda_env_list.txt" conda env list

  while IFS= read -r env_name; do
    [[ -z "$env_name" ]] && continue
    safe_env_name="$(printf '%s' "$env_name" | tr '/: ' '___')"
    safe_cmd "$OUTPUT_DIR/exports/conda_env_${safe_env_name}.yml" conda env export -n "$env_name" --no-builds
    safe_cmd "$OUTPUT_DIR/exports/conda_explicit_${safe_env_name}.txt" conda list -n "$env_name" --explicit
    safe_cmd "$OUTPUT_DIR/exports/pip_freeze_${safe_env_name}.txt" conda run -n "$env_name" python -m pip freeze
  done < <(conda env list | awk 'NR>2 && $1 != "*" {print $1}')
else
  warn "conda not found"
fi

if command -v mamba >/dev/null 2>&1; then
  safe_cmd "$OUTPUT_DIR/exports/mamba_info.txt" mamba info
else
  warn "mamba not found"
fi

log "Recording PRS software paths"
cat > "$OUTPUT_DIR/versions/prs_software_paths.tsv" <<PATHS
software	path	detected
PRSice.R	${PRSICE_R_PATH:-NOT_FOUND}	$([[ -n "${PRSICE_R_PATH:-}" ]] && echo yes || echo no)
PRSice_dir	${PRSICE_DIR:-NOT_FOUND}	$([[ -n "${PRSICE_DIR:-}" ]] && echo yes || echo no)
PRScs_dir	${PRSCS_DIR:-NOT_FOUND}	$([[ -n "${PRSCS_DIR:-}" ]] && echo yes || echo no)
PRScs_script	${PRSCS_SCRIPT:-NOT_FOUND}	$([[ -n "${PRSCS_SCRIPT:-}" ]] && echo yes || echo no)
plink	${PLINK_PATH:-NOT_FOUND}	$([[ -n "${PLINK_PATH:-}" ]] && echo yes || echo no)
plink2	${PLINK2_PATH:-NOT_FOUND}	$([[ -n "${PLINK2_PATH:-}" ]] && echo yes || echo no)
PATHS

log "Collecting software versions"
VERSIONS_OUT="$OUTPUT_DIR/versions/prs_software_versions.txt"
: > "$VERSIONS_OUT"
[[ -n "${PLINK_PATH:-}" ]] && run_version_probe "plink" "$VERSIONS_OUT" "$PLINK_PATH" --version || warn "plink not found at $KNOWN_PLINK or PATH"
[[ -n "${PLINK2_PATH:-}" ]] && run_version_probe "plink2" "$VERSIONS_OUT" "$PLINK2_PATH" --version || warn "plink2 not found at $KNOWN_PLINK2 or PATH"
if [[ -n "${PRSICE_R_PATH:-}" ]]; then
  if command -v Rscript >/dev/null 2>&1; then
    run_version_probe "PRSice" "$VERSIONS_OUT" Rscript "$PRSICE_R_PATH" --version
    run_version_probe "PRSice help header" "$VERSIONS_OUT" Rscript "$PRSICE_R_PATH" --help
  else
    warn "Rscript not found; cannot query PRSice version"
  fi
else
  warn "PRSice.R not found at $KNOWN_PRSICE_R or PATH"
fi
if [[ -n "${PRSCS_DIR:-}" ]]; then
  {
    echo "=== PRS-CS ==="
    echo "Directory: $PRSCS_DIR"
    [[ -d "$PRSCS_DIR/.git" ]] && git -C "$PRSCS_DIR" rev-parse --short HEAD 2>/dev/null || true
    [[ -d "$PRSCS_DIR/.git" ]] && git -C "$PRSCS_DIR" describe --tags --always 2>/dev/null || true
    [[ -n "${PRSCS_SCRIPT:-}" ]] && echo "Script: $PRSCS_SCRIPT"
    echo
  } >> "$VERSIONS_OUT"
else
  warn "PRS-CS directory not found at $KNOWN_PRSCS_DIR"
fi

for tool in python python3 pip pip3 R Rscript conda mamba bcftools samtools tabix bgzip; do
  if command -v "$tool" >/dev/null 2>&1; then
    run_version_probe "$tool" "$VERSIONS_OUT" "$tool" --version
  fi
done

log "Generating PRSice run template"
cat > "$OUTPUT_DIR/run_prsice_template.sh" <<'PRSICE_TEMPLATE'
#!/usr/bin/env bash
set -euo pipefail

# PRSice schizophrenia PRS template.
# Fill in file paths before running. Do NOT commit real genotype/GWAS/phenotype data.

PRSICE_R="${PRSICE_R:-$HOME/bio_software/PRSice/PRSice.R}"
PRSICE_BIN="${PRSICE_BIN:-$HOME/bio_software/PRSice/PRSice_linux}"
PLINK="${PLINK:-$HOME/bio_software/plink}"

BASE_GWAS="/path/to/schizophrenia_gwas_sumstats.txt"   # GWAS summary statistics (not backed up)
TARGET_PREFIX="/path/to/target_genotype_prefix"         # prefix for .bed/.bim/.fam (not backed up)
PHENO_FILE="/path/to/phenotype.tsv"                     # sample phenotype/covariate file (not backed up)
OUT_DIR="prsice_results"

mkdir -p "$OUT_DIR"

Rscript "$PRSICE_R" \
  --prsice "$PRSICE_BIN" \
  --plink "$PLINK" \
  --base "$BASE_GWAS" \
  --target "$TARGET_PREFIX" \
  --pheno "$PHENO_FILE" \
  --binary-target F \
  --stat OR \
  --or \
  --snp SNP \
  --chr CHR \
  --bp BP \
  --A1 A1 \
  --A2 A2 \
  --pvalue P \
  --out "$OUT_DIR/schizophrenia_prsice"
PRSICE_TEMPLATE
chmod +x "$OUTPUT_DIR/run_prsice_template.sh"

log "Generating PRS-CS run template"
cat > "$OUTPUT_DIR/run_prscs_template.sh" <<'PRSCS_TEMPLATE'
#!/usr/bin/env bash
set -euo pipefail

# PRS-CS schizophrenia PRS template.
# Fill in file paths before running. Do NOT commit real genotype/GWAS/LD reference data.

PRSCS_DIR="${PRSCS_DIR:-$HOME/bio_software/PRScs}"
PYTHON="${PYTHON:-python}"

REF_DIR="/path/to/ldblk_1kg_eas"                    # LD reference directory (not backed up)
BIM_PREFIX="/path/to/target_genotype_prefix"         # prefix for target .bim (not backed up)
SUMSTATS="/path/to/schizophrenia_gwas_sumstats.txt"  # GWAS summary statistics (not backed up)
OUT_DIR="prscs_results"
N_GWAS="100000"                                      # replace with GWAS sample size

mkdir -p "$OUT_DIR"

"$PYTHON" "$PRSCS_DIR/PRScs.py" \
  --ref_dir="$REF_DIR" \
  --bim_prefix="$BIM_PREFIX" \
  --sst_file="$SUMSTATS" \
  --n_gwas="$N_GWAS" \
  --chrom=1 \
  --phi=1e-2 \
  --out_dir="$OUT_DIR" \
  --out_name="schizophrenia_prscs"
PRSCS_TEMPLATE
chmod +x "$OUTPUT_DIR/run_prscs_template.sh"

log "Generating restore_prs_environment.sh"
cat > "$OUTPUT_DIR/restore_prs_environment.sh" <<'RESTORE'
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
RESTORE
chmod +x "$OUTPUT_DIR/restore_prs_environment.sh"

# Keep the original generic installer name as a compatibility wrapper.
cat > "$OUTPUT_DIR/install_local.sh" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/restore_prs_environment.sh" "$@"
INSTALL
chmod +x "$OUTPUT_DIR/install_local.sh"

log "Generating .gitignore"
cat > "$OUTPUT_DIR/.gitignore" <<'GITIGNORE'
# Genotype binary files (never back up raw target genotype data)
*.bed
*.bim
*.fam
*.pgen
*.pvar
*.psam

# GWAS summary statistics and compressed large files
*.gz
*.bgz
*.zip
*.tar
*.tar.gz
*GWAS*
*gwas*
*sumstats*
*summary_statistics*

# LD reference blocks / reference panels
ldblk_1kg_eas/
ldblk_1kg_eur/
ldblk_1kg_afr/
ldblk_1kg_amr/
ldblk_1kg_sas/
LD_reference/
reference_panel/

# Raw genomic or phenotype data directories (edit for your project)
raw_data/
raw_genotype/
genotype/
gwas/
input_data/
phenotype/
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

log "Generating PRS environment summary"
cat > "$OUTPUT_DIR/prs_environment_summary.md" <<SUMMARY
# Schizophrenia PRS Environment Summary

Generated on: $(date -Is)
Host: $(hostname 2>/dev/null || echo unknown)
User: ${USER:-unknown}

## Detected core PRS software

| Software | Detected path | Status |
|---|---|---|
| PRSice.R | ${PRSICE_R_PATH:-NOT_FOUND} | $([[ -n "${PRSICE_R_PATH:-}" ]] && echo detected || echo missing) |
| PRSice directory | ${PRSICE_DIR:-NOT_FOUND} | $([[ -n "${PRSICE_DIR:-}" ]] && echo detected || echo missing) |
| PRS-CS directory | ${PRSCS_DIR:-NOT_FOUND} | $([[ -n "${PRSCS_DIR:-}" ]] && echo detected || echo missing) |
| PRS-CS script | ${PRSCS_SCRIPT:-NOT_FOUND} | $([[ -n "${PRSCS_SCRIPT:-}" ]] && echo detected || echo missing) |
| plink | ${PLINK_PATH:-NOT_FOUND} | $([[ -n "${PLINK_PATH:-}" ]] && echo detected || echo missing) |
| plink2 | ${PLINK2_PATH:-NOT_FOUND} | $([[ -n "${PLINK2_PATH:-}" ]] && echo detected || echo missing) |

## Known server paths checked

- PRSice: \`~/bio_software/PRSice/PRSice.R\`
- PRS-CS: \`~/bio_software/PRScs\`
- plink: \`~/bio_software/plink\`
- plink2: \`~/software/plink2\`

## Captured files

- Conda/mamba exports: \`exports/\`
- Shell config backups: \`configs/bashrc.backup\`, \`configs/bash_profile.backup\`, \`configs/profile.backup\`
- Full PATH entries: \`configs/path_entries.txt\`
- Genetics-related PATH entries: \`configs/genetics_path_entries.txt\`
- Software paths: \`versions/prs_software_paths.tsv\`
- Software versions: \`versions/prs_software_versions.txt\`
- PRSice template: \`run_prsice_template.sh\`
- PRS-CS template: \`run_prscs_template.sh\`
- Restore script: \`restore_prs_environment.sh\`

## Data policy

This backup intentionally records software paths, package exports, and command templates only. It does **not** copy genotype files, GWAS summary statistics, phenotype tables, LD reference blocks, or other large/raw data files.

Review \`configs/env_vars_full.review_before_push.txt\` before pushing to GitHub, because environment variables can contain tokens or private paths.
SUMMARY

log "Generating README.md"
cat > "$OUTPUT_DIR/README.md" <<'README'
# Schizophrenia PRS Environment Backup

This folder is a reproducible backup of a Linux software environment for schizophrenia PRS analysis with **PRSice + PRS-CS**.

It stores software metadata and install/restore scripts only. It deliberately does **not** store genotype data, GWAS summary statistics, LD reference panels, phenotype files, or raw sequencing data.

## Contents

- `prs_environment_summary.md` — automatically generated summary of detected PRS software and server paths.
- `exports/` — conda/mamba environment exports and pip package snapshots.
- `configs/` — shell configuration backups, full PATH, genetics-related PATH entries, and environment variables for review.
- `versions/` — detected software locations and version probe output.
- `run_prsice_template.sh` — standard PRSice schizophrenia PRS run template with placeholder paths.
- `run_prscs_template.sh` — standard PRS-CS run template with placeholder paths.
- `restore_prs_environment.sh` — restore script for a new Linux server.
- `install_local.sh` — compatibility wrapper that calls `restore_prs_environment.sh`.
- `previous_generated_metadata/` — small previously generated metadata preserved when rerunning into an existing backup folder.
- `.gitignore` — excludes genotype, GWAS, LD reference, raw data, compressed archives, and secrets.

## Generate this backup on the remote server

```bash
bash backup_env.sh
# or use a custom output directory
bash backup_env.sh env_backup_scz_prs
```

## Restore on another Linux server

1. Install Miniconda or Mambaforge.
2. Copy this `env_backup` folder to the new server.
3. Run:

```bash
cd env_backup
bash restore_prs_environment.sh
```

4. Add the PATH lines printed by the restore script to `~/.bashrc`.
5. Edit `run_prsice_template.sh` and `run_prscs_template.sh` to point to local genotype/GWAS/LD-reference files.

## GitHub upload steps

Before pushing, inspect `configs/env_vars_full.review_before_push.txt` and remove any token/password/private path if present. If you reran the backup in an existing folder, review `previous_generated_metadata/` as well; it contains only small metadata snapshots and intentionally skips large genotype/GWAS/LD files.

```bash
cd env_backup
git init
git add .
git commit -m "backup: schizophrenia PRS software environment"
git branch -M main
git remote add origin <YOUR_GITHUB_REPO_URL>
git push -u origin main
```

## Important data exclusions

Do not commit:

- `*.bed`, `*.bim`, `*.fam`, `*.pgen`, `*.pvar`, `*.psam`
- GWAS summary statistics
- `ldblk_1kg_eas/` or any LD reference directory
- raw genotype, sequencing, phenotype, or clinical data
- SSH keys, tokens, passwords, or `.env` files
README

log "Done. Schizophrenia PRS backup directory created: $OUTPUT_DIR"

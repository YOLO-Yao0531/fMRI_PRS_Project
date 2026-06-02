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

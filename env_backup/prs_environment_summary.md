# Schizophrenia PRS Environment Summary

Generated on: 2026-06-02T17:10:40+08:00
Host: alimalinux9.5
User: yaolei

## Detected core PRS software

| Software | Detected path | Status |
|---|---|---|
| PRSice.R | /ifs1/User/yaolei/bio_software/PRSice/PRSice.R | detected |
| PRSice directory | /ifs1/User/yaolei/bio_software/PRSice | detected |
| PRS-CS directory | NOT_FOUND | missing |
| PRS-CS script | NOT_FOUND | missing |
| plink | /ifs1/User/yaolei/miniforge3/bin/plink | detected |
| plink2 | /ifs1/User/yaolei/bio_software/plink/plink2 | detected |

## Known server paths checked

- PRSice: `~/bio_software/PRSice/PRSice.R`
- PRS-CS: `~/bio_software/PRScs`
- plink: `~/bio_software/plink`
- plink2: `~/software/plink2`

## Captured files

- Conda/mamba exports: `exports/`
- Shell config backups: `configs/bashrc.backup`, `configs/bash_profile.backup`, `configs/profile.backup`
- Full PATH entries: `configs/path_entries.txt`
- Genetics-related PATH entries: `configs/genetics_path_entries.txt`
- Software paths: `versions/prs_software_paths.tsv`
- Software versions: `versions/prs_software_versions.txt`
- PRSice template: `run_prsice_template.sh`
- PRS-CS template: `run_prscs_template.sh`
- Restore script: `restore_prs_environment.sh`

## Data policy

This backup intentionally records software paths, package exports, and command templates only. It does **not** copy genotype files, GWAS summary statistics, phenotype tables, LD reference blocks, or other large/raw data files.

Review `configs/env_vars_full.review_before_push.txt` before pushing to GitHub, because environment variables can contain tokens or private paths.

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

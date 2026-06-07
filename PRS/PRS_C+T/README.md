# PRSice C+T workflow

This folder contains scripts for calculating schizophrenia PRS with PRSice C+T.

## Scripts

- `scripts/run_prsice_highres.sh`: runs PRSice using `PGC_SCZ.QC.gz`, `impute_qc`, EAS LD reference, `SCZ.txt`, and optional `PCA_with_header.txt`.
- `scripts/extract_best_pt_from_prsice.R`: extracts the best p-value threshold by maximum model-fit R2 from `.prsice`.
- `scripts/prs_threshold_logistic_scan.R`: reruns threshold-wise logistic regressions from PRSice all-score output.
- `scripts/plot_prsice_fig1_style.R`: draws the two-panel PRSice figure.

## Main outputs

- `PRSice_SCZ_highres.prsice`: threshold-level PRSice model results.
- `PRSice_SCZ_highres.all_score`: per-subject PRS scores.
- `best_PT_summary.txt`: best threshold summary.
- `PRS_threshold_logistic_results.txt`: threshold-wise logistic regression results.
- `PRSice_SCZ_highres_fig1_style.png` and `.pdf`: figure outputs.

## Example

```bash
cd ~/Data_GENE/PRSice_C+T

nohup env THREAD=8 \
LOWER=0.0001 \
UPPER=0.5 \
INTERVAL=0.00005 \
RUN_PLINK_ROUND1=false \
LDREF=EAS_phase3_plink1_nodup \
bash scripts/run_prsice_highres.sh > PRSice_SCZ_highres.run.log 2>&1 &

Rscript scripts/extract_best_pt_from_prsice.R
Rscript scripts/prs_threshold_logistic_scan.R
Rscript scripts/plot_prsice_fig1_style.R
```

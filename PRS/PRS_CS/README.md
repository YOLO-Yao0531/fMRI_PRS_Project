# PRS-CS workflow

This folder contains scripts for calculating schizophrenia PRS with PRS-CS using the Asian PGC3 SCZ summary statistics.

## Scripts

- `scripts/rebuild_pgc_scz_asian_base.sh`: rebuilds `PGC_SCZ.QC.gz` from `PGC3_SCZ_wave3.asian.autosome.public.v3.vcf.tsv.gz` using header-based columns, `IMPINFO >= 0.8`, estimated `MAF >= 0.01`, duplicate-ID removal, and ambiguous SNP removal.
- `scripts/prscs_pipeline.sh`: converts the rebuilt base file to PRS-CS format, runs PRS-CS for chromosomes 1-22, merges posterior effects, scores target samples with PLINK, and writes standardized PRS.
- `scripts/prs_postprocess.R`: standardizes PLINK score output and merges PRS with `SCZ.txt`.

## Main outputs

- `prscs_out/SCZ_PRSCS_effects.txt`: merged posterior SNP effects.
- `prscs_out/SCZ_PRSCS_score_z.txt`: per-subject PRS and z-scored PRS.
- `prscs_out/SCZ_PRSCS_pheno_merged.txt`: phenotype plus PRS, usually the final analysis file.

## Example

```bash
cd ~/Data_GENE/PRSCS

nohup env \
WORK_DIR=$PWD \
PRSCS_PY=/ifs1/User/yaolei/bio_software/PRScs/PRScs.py \
PYTHON_BIN=/ifs1/User/yaolei/miniforge3/envs/prscs_py38/bin/python \
PLINK_BIN=/ifs1/User/yaolei/miniforge3/bin/plink \
bash scripts/prscs_pipeline.sh > prscs_pipeline_rerun.log 2>&1 &
```

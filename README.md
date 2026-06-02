# fMRI_PRS_Project

该仓库提供一个专用于精神分裂症 PRS（PRSice + PRS-CS）分析环境的可复现 Linux 备份脚本：

```bash
bash backup_env.sh
```

执行后会生成 `env_backup/`，包含：

- `prs_environment_summary.md`：当前服务器 PRS 环境自动汇总
- `run_prsice_template.sh`：PRSice 标准运行模板
- `run_prscs_template.sh`：PRS-CS 标准运行模板
- `restore_prs_environment.sh`：新 Linux 服务器恢复脚本
- conda/mamba 环境导出、pip 包、PATH、软件路径和版本、shell 配置备份
- `.gitignore`：排除 bed/bim/fam、GWAS、LD reference、原始基因数据和密钥

该脚本只记录路径模板和软件配置，不复制大型数据文件。

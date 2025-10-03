
# Azure Blob Storage Cost & Metadata Analyzer 🚀

This project is part of a **DevOps SRE Daily Challenge** where we replicated a **real-world cloud cost optimization scenario** in **Azure**.

---

## 📌 Challenge Recap

We had to:

1. **Print summary of each bucket (container)**  
   - Name, region, size (GB), versioning/metadata status.
2. **Identify large containers**  
   - >80GB and unused for 90+ days (highlight for audit).
3. **Generate cost report**  
   - Total estimated storage cost grouped by region and environment.
4. **Highlight cleanup/deletion/archival candidates**  
   - Size > 50GB → recommend cleanup.  
   - Size > 100GB & unused ≥20 days → deletion queue.  
   - Size 50–100GB & unused ≥30 days → archival (move to Archive/Glacier).  
5. **Produce final reports** for deletion, archival, highlights.

---

## 🏗️ Setup We Did

- Created **1 Azure subscription** (Free Tier).  
- Inside it, created **3 Resource Groups**:
  - `Prod`, `Test`, `Dev`
- Created **3 storage accounts**:
  - `stprodlogs01` (Production)
  - `stestlogs01` (Test)
  - `stdevlogs01` (Dev)
- Inside each storage account, created containers (`-logs`, `-backups`, `-reports`)  
- Uploaded test data:
  - Small files (20MB, 100MB)
  - One large file (`bigbackup4g.bin`, ~4GB) into `prod-backups`

We also set **container metadata**:
- `env=prod|test|dev`

---

## ⚙️ Analyzer Script

We wrote a **Cloud Shell–friendly Bash script** `azure_blob_analyzer_with_thresholds_fixed.sh` that:

- Lists containers and blobs using `az cli` (`--auth-mode login` → no keys required).
- Aggregates blob sizes, lastModified timestamps using `jq`.
- Calculates:
  - Total size per container
  - Days since last access (unused days)
  - Estimated monthly cost (`GB * $0.023`)
- Applies cleanup/deletion/archival rules.
- Outputs reports into `reports/` folder:
  - `container_summary.json`
  - `cost_report_by_region_env.csv`
  - `deletion_candidates.txt`
  - `archival_candidates.txt`
  - `highlight_region_unused_over_90.txt`

We fixed **type handling issues** (`jq: string and number cannot be added`) by ensuring all values were passed as JSON numbers using `--argjson`.

---

## 📊 Sample Output

### Container Summary


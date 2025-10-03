#!/usr/bin/env bash
# azure_blob_analyzer_with_thresholds_fixed.sh
# Safe Cloud Shell friendly analyzer with CLI-overridable thresholds
# Usage example:
#  ./azure_blob_analyzer_with_thresholds_fixed.sh --subscription <sub-id> --accounts stprodlogs01 --cleanup-gb 1 --deletion-gb 2 --deletion-days 0 --archive-min-gb 1 --archive-max-gb 10 --archive-days 0

set -euo pipefail
IFS=$'\n\t'

# Defaults
CLEANUP_GB_DEFAULT=50
DELETION_GB_DEFAULT=100
DELETION_DAYS_DEFAULT=20
ARCHIVE_MIN_GB_DEFAULT=50
ARCHIVE_MAX_GB_DEFAULT=100
ARCHIVE_DAYS_DEFAULT=30
PRICE_PER_GB_DEFAULT=0.023
OUTDIR="reports"

# Parse args (simple)
SUBSCRIPTION=""
ACCOUNTS=()
CLEANUP_GB="$CLEANUP_GB_DEFAULT"
DELETION_GB="$DELETION_GB_DEFAULT"
DELETION_DAYS="$DELETION_DAYS_DEFAULT"
ARCHIVE_MIN_GB="$ARCHIVE_MIN_GB_DEFAULT"
ARCHIVE_MAX_GB="$ARCHIVE_MAX_GB_DEFAULT"
ARCHIVE_DAYS="$ARCHIVE_DAYS_DEFAULT"
PRICE_PER_GB="$PRICE_PER_GB_DEFAULT"

show_help(){
  cat <<EOF
Usage: $0 --subscription <sub-id> [options]

Options:
  --subscription <id>         (required)
  --accounts a b c            optional storage account names
  --cleanup-gb <float>        default: $CLEANUP_GB_DEFAULT
  --deletion-gb <float>       default: $DELETION_GB_DEFAULT
  --deletion-days <int>       default: $DELETION_DAYS_DEFAULT
  --archive-min-gb <float>    default: $ARCHIVE_MIN_GB_DEFAULT
  --archive-max-gb <float>    default: $ARCHIVE_MAX_GB_DEFAULT
  --archive-days <int>        default: $ARCHIVE_DAYS_DEFAULT
  --price-per-gb <float>      default: $PRICE_PER_GB_DEFAULT
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUBSCRIPTION="$2"; shift 2;;
    --accounts) shift; while [[ $# -gt 0 && "$1" != --* ]]; do ACCOUNTS+=("$1"); shift; done;;
    --cleanup-gb) CLEANUP_GB="$2"; shift 2;;
    --deletion-gb) DELETION_GB="$2"; shift 2;;
    --deletion-days) DELETION_DAYS="$2"; shift 2;;
    --archive-min-gb) ARCHIVE_MIN_GB="$2"; shift 2;;
    --archive-max-gb) ARCHIVE_MAX_GB="$2"; shift 2;;
    --archive-days) ARCHIVE_DAYS="$2"; shift 2;;
    --price-per-gb) PRICE_PER_GB="$2"; shift 2;;
    -h|--help) show_help; exit 0;;
    *) echo "Unknown arg: $1"; show_help; exit 1;;
  esac
done

if [ -z "$SUBSCRIPTION" ]; then
  echo "Missing --subscription"
  exit 1
fi

# helpers
bytes_to_gb() { awk -v b="$1" 'BEGIN {printf "%.4f", b/(1024^3)}'; }
to_number() { awk -v v="$1" 'BEGIN {printf "%f", v+0}'; }   # ensure numeric formatting for jq --argjson
to_int() { awk -v v="$1" 'BEGIN {printf "%d", v+0}'; }

echo "Analyzer thresholds:"
echo "  cleanup_gb: $CLEANUP_GB  deletion_gb: $DELETION_GB  deletion_days: $DELETION_DAYS"
echo "  archive_range: $ARCHIVE_MIN_GB - $ARCHIVE_MAX_GB GB  archive_days: $ARCHIVE_DAYS"
echo "  price_per_gb: $PRICE_PER_GB"
echo "Using subscription: $SUBSCRIPTION"

az account set --subscription "$SUBSCRIPTION"

mkdir -p "$OUTDIR"
SUMMARY_JSON="$OUTDIR/container_summary.json"
COST_CSV="$OUTDIR/cost_report_by_region_env.csv"
DELETION_JSON="$OUTDIR/deletion_queue.json"
DELETION_TXT="$OUTDIR/deletion_candidates.txt"
ARCHIVE_TXT="$OUTDIR/archival_candidates.txt"
HIGHLIGHT_TXT="$OUTDIR/highlight_region_unused_over_90.txt"

# init outputs
echo "[]" > "$SUMMARY_JSON"
echo "region,env,monthly_cost_estimate" > "$COST_CSV"
jq -n '[]' > "$DELETION_JSON"
: > "$DELETION_TXT"
: > "$ARCHIVE_TXT"
: > "$HIGHLIGHT_TXT"

TMP_COSTS="$(mktemp)"
: > "$TMP_COSTS"
now_epoch=$(date +"%s")

# discover accounts if not provided
if [ ${#ACCOUNTS[@]} -eq 0 ]; then
  mapfile -t ACCOUNTS < <(az storage account list --query "[].name" -o tsv 2>/dev/null || true)
fi
echo "Accounts to scan: ${ACCOUNTS[*]}"

for acct in "${ACCOUNTS[@]}"; do
  echo "Scanning storage account: $acct"
  region="$(az storage account show --name "$acct" --query location -o tsv 2>/dev/null || echo unknown)"

  mapfile -t CONTAINERS < <(az storage container list --account-name "$acct" --auth-mode login --query "[].name" -o tsv 2>/dev/null || true)
  if [ "${#CONTAINERS[@]}" -eq 0 ]; then
    echo "  No containers or permission issue for $acct"
    continue
  fi

  for container in "${CONTAINERS[@]}"; do
    echo "  Container: $container"
    meta_json="$(az storage container metadata show --account-name "$acct" --name "$container" --auth-mode login -o json 2>/dev/null || echo "{}")"
    env="$(echo "$meta_json" | jq -r '."env" // "unknown"')"
    dept="$(echo "$meta_json" | jq -r '."department" // "unknown"')"

    blobs_json="$(az storage blob list --account-name "$acct" --container-name "$container" --auth-mode login -o json 2>/dev/null || echo '[]')"

    if [ "$(echo "$blobs_json" | jq 'length')" -eq 0 ]; then
      size_bytes=0
      latest="null"
      blob_count=0
    else
      # numeric sum and latest using jq (safe)
      size_bytes=$(echo "$blobs_json" | jq '[.[] | (.properties.contentLength // 0)] | add')
      latest=$(echo "$blobs_json" | jq -r '[.[] | (.properties.lastModified // null)] | map(select(.!=null)) | max // null')
      blob_count=$(echo "$blobs_json" | jq 'length')
    fi

    # format numeric values reliably
    size_gb=$(bytes_to_gb "$size_bytes")
    size_gb_json=$(to_number "$size_gb")
    blob_count_json=$(to_int "$blob_count")

    if [ "$latest" = "null" ] || [ -z "$latest" ]; then
      days_unused_json="null"
    else
      lm_epoch=$(date -d "$latest" +"%s" 2>/dev/null || date -d "${latest/Z/+0000}" +"%s")
      diff=$(( now_epoch - lm_epoch ))
      days_unused=$(awk -v d=$diff 'BEGIN{printf "%.2f", d/86400}')
      days_unused_json=$(to_number "$days_unused")
    fi

    monthly_cost=$(awk -v s="$size_gb" -v p="$PRICE_PER_GB" 'BEGIN {printf "%.4f", s*p}')
    monthly_cost_json=$(to_number "$monthly_cost")

    # Build entry using jq -n with numeric values via --argjson (types preserved)
    if [ "$latest" = "null" ] || [ -z "$latest" ]; then
      # days_unused is null
      entry_json=$(jq -n \
        --arg acct "$acct" --arg container "$container" --arg region "$region" \
        --arg env "$env" --arg dept "$dept" \
        --argjson size_gb "$size_gb_json" --argjson blob_count "$blob_count_json" \
        --argjson monthly_cost "$monthly_cost_json" \
        '{
          storage_account:$acct,
          container:$container,
          region:$region,
          env:$env,
          department:$dept,
          size_gb:$size_gb,
          blob_count:$blob_count,
          days_unused:null,
          monthly_cost:$monthly_cost
        }')
    else
      entry_json=$(jq -n \
        --arg acct "$acct" --arg container "$container" --arg region "$region" \
        --arg env "$env" --arg dept "$dept" \
        --argjson size_gb "$size_gb_json" --argjson blob_count "$blob_count_json" \
        --argjson days_unused "$days_unused_json" --argjson monthly_cost "$monthly_cost_json" \
        '{
          storage_account:$acct,
          container:$container,
          region:$region,
          env:$env,
          department:$dept,
          size_gb:$size_gb,
          blob_count:$blob_count,
          days_unused:$days_unused,
          monthly_cost:$monthly_cost
        }')
    fi

    # Append entry_json to summary file using jq with --argjson
    tmp=$(mktemp)
    jq --argjson entry "$entry_json" '. + [$entry]' "$SUMMARY_JSON" > "$tmp" && mv "$tmp" "$SUMMARY_JSON"

    # cost grouping
    echo "${region}|||${env} ${monthly_cost}" >> "$TMP_COSTS"

    # Rules (use numeric comparisons via awk)
    if [ "$(awk -v s="$size_gb" -v t="$CLEANUP_GB" 'BEGIN{print (s>=t)?1:0}')" -eq 1 ]; then
      echo "  -> Recommend cleanup: ${acct}/${container} size ${size_gb} GB"
    fi

    # highlight fixed values (80GB,90days)
    if [ "$(awk -v s="$size_gb" 'BEGIN{print (s>80)?1:0}')" -eq 1 ] && [ "$days_unused_json" != "null" ]; then
      if [ "$(awk -v d="$days_unused" 'BEGIN{print (d>=90)?1:0}')" -eq 1 ]; then
        echo "${region}: ${acct}/${container}" >> "$HIGHLIGHT_TXT"
      fi
    fi

    # Deletion candidate: size > DELETION_GB and unused >= DELETION_DAYS (or unknown)
    if [ "$(awk -v s="$size_gb" -v t="$DELETION_GB" 'BEGIN{print (s>t)?1:0}')" -eq 1 ]; then
      add_del=0
      if [ "$days_unused_json" = "null" ]; then
        add_del=1
      else
        if [ "$(awk -v d="$days_unused" -v thresh="$DELETION_DAYS" 'BEGIN{print (d>=thresh)?1:0}')" -eq 1 ]; then
          add_del=1
        fi
      fi
      if [ "$add_del" -eq 1 ]; then
        dtmp=$(mktemp)
        jq -n --arg acct "$acct" --arg container "$container" --arg region "$region" --arg env "$env" \
          --argjson size_gb "$size_gb_json" --argjson days_unused "${days_unused_json:-null}" \
          '{storage_account:$acct,container:$container,region:$region,env:$env,size_gb:$size_gb,days_unused:$days_unused,reason:"Size>DELETION_GB and not accessed in DELETION_DAYS (or unknown)"}' \
          > "$dtmp"
        # append to deletion json array
        tmpd=$(mktemp)
        jq --slurpfile new "$dtmp" '. + ($new|.)' "$DELETION_JSON" > "$tmpd" && mv "$tmpd" "$DELETION_JSON"
        echo "${acct}/${container} | region:${region} | env:${env} | size:${size_gb} GB | days_unused:${days_unused:-unknown}" >> "$DELETION_TXT"
      fi
    fi

    # Archival suggestion
    if [ "$(awk -v s="$size_gb" -v a="$ARCHIVE_MIN_GB" -v b="$ARCHIVE_MAX_GB" 'BEGIN{print (s>=a && s<=b)?1:0}')" -eq 1 ] && [ "$days_unused_json" != "null" ]; then
      if [ "$(awk -v d="$days_unused" -v thresh="$ARCHIVE_DAYS" 'BEGIN{print (d>=thresh)?1:0}')" -eq 1 ]; then
        echo "${acct}/${container} | region:${region} | env:${env} | size:${size_gb} GB | days_unused:${days_unused}" >> "$ARCHIVE_TXT"
      fi
    fi

  done
done

# collapse TMP_COSTS
awk '{sum[$1]+=$2} END{for(k in sum){split(k,a,"|||"); printf "%s,%s,%.4f\n",a[1],a[2],sum[k]}}' "$TMP_COSTS" >> "$COST_CSV"
rm -f "$TMP_COSTS"

echo
echo "Reports generated in: $OUTDIR"
echo "Summary JSON: $SUMMARY_JSON"
echo "Cost CSV: $COST_CSV"
echo "Deletion JSON: $DELETION_JSON"
echo "Deletion TXT: $DELETION_TXT"
echo "Archival TXT: $ARCHIVE_TXT"
echo "Highlights: $HIGHLIGHT_TXT"
echo


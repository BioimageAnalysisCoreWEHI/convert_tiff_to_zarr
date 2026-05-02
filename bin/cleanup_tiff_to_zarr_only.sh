#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cleanup_tiff_to_zarr_only.sh
#
# Surgical cleanup: removes ONLY work directories created by the
# convert_tiff_to_zarr pipeline (identified by `ngff-zarr` calls in their
# .command.sh). Leaves every other pipeline's work dirs untouched, so you
# can still `-resume` other runs sharing the same work tree.
#
# Usage:
#   ./cleanup_tiff_to_zarr_only.sh <work_dir> [--apply]
#
# Examples:
#   # Preview
#   ./cleanup_tiff_to_zarr_only.sh /scratch/users/mckay.m/nextflow/work
#
#   # Actually delete
#   ./cleanup_tiff_to_zarr_only.sh /scratch/users/mckay.m/nextflow/work --apply
# -----------------------------------------------------------------------------
set -euo pipefail

WORK_ROOT=""
APPLY=0
SIGNATURE="${SIGNATURE:-ngff-zarr}"   # token that uniquely identifies our tasks

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)     APPLY=1; shift ;;
        --signature) SIGNATURE="$2"; shift 2 ;;
        -h|--help)   sed -n '2,18p' "$0"; exit 0 ;;
        -*)          echo "Unknown flag: $1" >&2; exit 2 ;;
        *)           WORK_ROOT="$1"; shift ;;
    esac
done

if [[ -z "$WORK_ROOT" || ! -d "$WORK_ROOT" ]]; then
    echo "Usage: $0 <work_dir> [--apply]" >&2
    exit 2
fi

human() { numfmt --to=iec-i --suffix=B --padding=8 "$1" 2>/dev/null || echo "${1}B"; }

echo "==> Scanning task dirs under: $WORK_ROOT"
echo "==> Matching signature in .command.sh: '$SIGNATURE'"
echo

# Nextflow task dirs are work/<2-char>/<long-hash>/.command.sh
mapfile -t hits < <(
    find "$WORK_ROOT" -mindepth 3 -maxdepth 3 -type f -name '.command.sh' \
        -exec grep -l -- "$SIGNATURE" {} + 2>/dev/null
)

if [[ ${#hits[@]} -eq 0 ]]; then
    echo "No matching task directories found."
    exit 0
fi

total_bytes=0
total_files=0
declare -a targets

for cmd in "${hits[@]}"; do
    task_dir="$(dirname "$cmd")"
    bytes=$(du -sb "$task_dir" 2>/dev/null | awk '{print $1}'); bytes=${bytes:-0}
    files=$(find "$task_dir" 2>/dev/null | wc -l); files=${files:-0}
    printf '  %-12s %-12s  %s\n' "$(human "$bytes")" "${files} files" "$task_dir"
    total_bytes=$((total_bytes + bytes))
    total_files=$((total_files + files))
    targets+=("$task_dir")
done

echo
echo "============================================================"
echo " Matched ${#targets[@]} task dirs"
echo " Would reclaim: $(human "$total_bytes")  /  ${total_files} files"
echo "============================================================"

if [[ $APPLY -eq 0 ]]; then
    echo
    echo "DRY-RUN. Re-run with --apply to actually delete."
    exit 0
fi

read -r -p "Type 'DELETE' to confirm removal of ${#targets[@]} task dirs: " confirm
[[ "$confirm" == "DELETE" ]] || { echo "Aborted."; exit 1; }

# Parallel rm to chew through millions of zarr chunk files
printf '%s\0' "${targets[@]}" | xargs -0 -n1 -P 4 rm -rf --

# Best-effort: remove now-empty 2-char parent dirs (work/ab/, work/c0/, etc.)
find "$WORK_ROOT" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true

echo "Done. Reclaimed approximately $(human "$total_bytes")."

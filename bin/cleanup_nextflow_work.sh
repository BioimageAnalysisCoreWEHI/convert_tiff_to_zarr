#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# cleanup_nextflow_work.sh
#
# Free up scratch quota by removing leftover Nextflow `work/` directories,
# orphaned .ome.zarr stores, and dask spill caches.
#
# Defaults to DRY-RUN: prints what *would* be removed and the disk space /
# inode count it would reclaim. Pass --apply to actually delete.
#
# Usage:
#   ./cleanup_nextflow_work.sh [PATH ...] [--apply] [--keep-latest] [--age DAYS]
#
# Examples:
#   # See what's eating /scratch (no deletion)
#   ./cleanup_nextflow_work.sh /scratch/$USER
#
#   # Actually delete everything older than 1 day, keeping the most recent run
#   ./cleanup_nextflow_work.sh /scratch/$USER --apply --keep-latest --age 1
#
#   # Multiple roots
#   ./cleanup_nextflow_work.sh /scratch/$USER /vast/scratch/$USER --apply
# -----------------------------------------------------------------------------
set -euo pipefail

APPLY=0
KEEP_LATEST=0
AGE_DAYS=0
ROOTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)        APPLY=1; shift ;;
        --keep-latest)  KEEP_LATEST=1; shift ;;
        --age)          AGE_DAYS="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,22p' "$0"; exit 0 ;;
        -*)
            echo "Unknown flag: $1" >&2; exit 2 ;;
        *)
            ROOTS+=("$1"); shift ;;
    esac
done

if [[ ${#ROOTS[@]} -eq 0 ]]; then
    ROOTS=("${NXF_WORK:-$PWD/work}")
fi

# ---- helpers ---------------------------------------------------------------

human() {  # bytes -> human-readable
    numfmt --to=iec-i --suffix=B --padding=8 "$1" 2>/dev/null || echo "$1B"
}

is_nextflow_work_dir() {
    # A Nextflow work dir contains 2-char hash subdirs each holding a longer
    # hash dir with a .command.sh inside. Cheap heuristic: see if there's at
    # least one */.command.sh two levels down.
    local d="$1"
    [[ -d "$d" ]] || return 1
    compgen -G "$d/??/*/.command.sh" >/dev/null
}

reclaim_total_bytes=0
reclaim_total_files=0
delete_paths=()

# ---- discovery -------------------------------------------------------------

for root in "${ROOTS[@]}"; do
    if [[ ! -d "$root" ]]; then
        echo "Skip (not a directory): $root" >&2
        continue
    fi

    echo "==> Scanning: $root"

    # Candidate dirs:
    #   1. Anything literally named `work` containing nextflow task dirs
    #   2. Stray *.ome.zarr stores left in work/ trees from killed runs
    #   3. dask cache dirs named `cache` or `dask-cache` next to a work dir
    mapfile -t candidates < <(
        {
            find "$root" -maxdepth 4 -type d -name 'work' -prune 2>/dev/null
            find "$root" -maxdepth 6 -type d -name '*.ome.zarr' -prune 2>/dev/null
            find "$root" -maxdepth 4 -type d \( -name 'cache' -o -name 'dask-cache' \) -prune 2>/dev/null
        } | sort -u
    )

    # Optionally exclude the most recently modified work dir
    if [[ $KEEP_LATEST -eq 1 ]]; then
        latest=$(printf '%s\n' "${candidates[@]}" \
                 | grep -E '/work$' \
                 | xargs -I{} stat -c '%Y {}' {} 2>/dev/null \
                 | sort -nr | head -1 | awk '{print $2}')
        if [[ -n "${latest:-}" ]]; then
            echo "    (keeping latest work dir: $latest)"
            candidates=("${candidates[@]/$latest}")
        fi
    fi

    for c in "${candidates[@]}"; do
        [[ -z "$c" ]] && continue
        [[ -d "$c" ]] || continue

        # Age filter
        if [[ $AGE_DAYS -gt 0 ]]; then
            if [[ -z "$(find "$c" -maxdepth 0 -mtime +$((AGE_DAYS-1)) -print 2>/dev/null)" ]]; then
                continue
            fi
        fi

        # For top-level work/ dirs, sanity-check that it really is a nextflow work tree
        if [[ "$(basename "$c")" == "work" ]] && ! is_nextflow_work_dir "$c"; then
            continue
        fi

        bytes=$(du -sb "$c" 2>/dev/null | awk '{print $1}'); bytes=${bytes:-0}
        files=$(find "$c" 2>/dev/null | wc -l); files=${files:-0}

        printf '    %-12s %-10s  %s\n' "$(human "$bytes")" "${files} files" "$c"

        reclaim_total_bytes=$((reclaim_total_bytes + bytes))
        reclaim_total_files=$((reclaim_total_files + files))
        delete_paths+=("$c")
    done
done

echo
echo "============================================================"
echo " Would reclaim: $(human "$reclaim_total_bytes")  /  ${reclaim_total_files} files"
echo " Targets:       ${#delete_paths[@]} directories"
echo "============================================================"

if [[ ${#delete_paths[@]} -eq 0 ]]; then
    echo "Nothing to do."; exit 0
fi

if [[ $APPLY -eq 0 ]]; then
    echo
    echo "DRY-RUN. Re-run with --apply to actually delete."
    exit 0
fi

read -r -p "Type 'DELETE' to confirm removal: " confirm
if [[ "$confirm" != "DELETE" ]]; then
    echo "Aborted."; exit 1
fi

echo "Deleting..."
# Parallel rm to chew through millions of zarr chunks faster than serial rm -rf
printf '%s\0' "${delete_paths[@]}" \
    | xargs -0 -n1 -P 4 rm -rf --

echo "Done. Reclaimed approximately $(human "$reclaim_total_bytes")."

#!/bin/bash
#SBATCH --job-name=cleanup_tiff_to_zarr
#SBATCH --output=cleanup_tiff_to_zarr_%j.log
#SBATCH --error=cleanup_tiff_to_zarr_%j.err
#SBATCH --time=08:00:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=8

# -----------------------------------------------------------------------------
# Delete only convert_tiff_to_zarr work dirs from /vast/scratch.
# Reads the precomputed target list from /tmp/tiff_to_zarr_targets.txt.
# -----------------------------------------------------------------------------
set -euo pipefail

WORK_ROOT="/vast/scratch/users/mckay.m/nextflow/work"
# NOTE: must be on shared storage (e.g. /vast or /stornext), NOT /tmp,
# because /tmp is node-local and won't be visible to the compute node.
TARGETS="${TARGETS:-/vast/scratch/users/mckay.m/tiff_to_zarr_targets.txt}"

echo "Starting cleanup on $(hostname) at $(date)"
echo "Work root : $WORK_ROOT"
echo "Targets   : $TARGETS"

if [[ ! -s "$TARGETS" ]]; then
    echo "ERROR: target list is missing or empty. Re-run the find/grep step first." >&2
    exit 1
fi

echo "Target count: $(wc -l < "$TARGETS")"

# Safety check: every line must live under WORK_ROOT — abort if any don't.
if grep -vF "$WORK_ROOT/" "$TARGETS" > /tmp/cleanup_outside.txt; then
    if [[ -s /tmp/cleanup_outside.txt ]]; then
        echo "ERROR: target list contains paths outside $WORK_ROOT:" >&2
        head /tmp/cleanup_outside.txt >&2
        exit 1
    fi
fi

echo
echo "Total size to reclaim:"
xargs -a "$TARGETS" du -sh --total 2>/dev/null | tail -1
echo

echo "Deleting with ${SLURM_CPUS_PER_TASK:-8} parallel rm workers..."
xargs -a "$TARGETS" -n1 -P "${SLURM_CPUS_PER_TASK:-8}" rm -rf --

echo
echo "Removing now-empty 2-char parent dirs under $WORK_ROOT..."
find "$WORK_ROOT" -mindepth 1 -maxdepth 1 -type d -empty -delete

echo
echo "Filesystem usage after cleanup:"
df -h "$WORK_ROOT" || true

echo "Job finished at $(date)"

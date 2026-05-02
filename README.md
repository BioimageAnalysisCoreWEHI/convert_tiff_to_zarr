# convert_tiff_to_zarr

Parallelisable Nextflow pipeline that converts large multi-channel TIFF images
to OME-Zarr using [ngff-zarr](https://github.com/thewtex/ngff-zarr).  
Point it at a directory of `.tif`, `.tiff`, `.ome.tif`, or `.ome.tiff` files —
each file is submitted as an independent job, making the pipeline trivially
parallel on HPC (SLURM) or cloud via [Seqera Platform](https://seqera.io).

## Requirements

- Nextflow ≥ 24.04
- One of: conda, Docker, Singularity/Apptainer, or a pre-installed `ngff-zarr`

## Quick start (command line)

```bash
# Local run, conda environment auto-created
nextflow run main.nf \
  -profile conda \
  --input_dir '/data/images' \
  --outdir results

# SLURM cluster + singularity (build container first — see below)
nextflow run main.nf \
  -profile medium,singularity \
  --input_dir '/hpc/data/images' \
  --outdir /hpc/results \
  --memory_target 64GB
```

## Running via Seqera Platform

[Seqera Platform](https://seqera.io) (formerly Nextflow Tower) provides a web UI
to launch, monitor, and manage pipeline runs on HPC or cloud.

### 1. Add the pipeline

In Seqera Platform → **Launchpad** → **Add pipeline**:
- **Pipeline**: point to your GitHub/GitLab repo URL for this pipeline
- **Revision**: branch or tag (e.g. `main`)
- **Config profiles**: choose your compute profile, e.g. `medium,singularity`

### 2. Configure a Compute Environment

Set up a Compute Environment matching your cluster (SLURM, AWS Batch, Google
Batch, Azure Batch). Seqera automatically injects `TOWER_ACCESS_TOKEN` —
no manual token configuration required.

### 3. Launch

In the Launch form, fill in at minimum:

| Parameter | Example value |
|---|---|
| `input_dir` | `/stornext/data/project/images` |
| `outdir` | `/stornext/data/project/results` |

All other parameters are optional and appear in the Seqera launch form
populated from `nextflow_schema.json`.

### 4. Monitor

Seqera shows per-job status, resource usage, and retry history. Conversion
logs for each TIFF are published to `outdir/logs/` and surfaced as a report
in the platform UI via `tower.yml`.

### Manual CLI with Seqera monitoring

```bash
export TOWER_ACCESS_TOKEN=<your Seqera token>
nextflow run main.nf -profile medium,singularity \
  --input_dir '/hpc/data/images' \
  --outdir results
```

## Profiles

| Profile | Executor | Use when |
|---|---|---|
| *(none)* | local | testing on a workstation |
| `small` | SLURM | images < 64 GB each |
| `medium` | SLURM | images 64–128 GB each |
| `large` | SLURM | images > 128 GB each |

Combine a container/environment profile with an HPC profile:
`-profile medium,singularity`

## Container build

```bash
# Docker
docker build -t ngff-zarr:latest .

# Singularity / Apptainer (from Docker image)
singularity build ngff-zarr.sif docker-daemon://ngff-zarr:latest
```

## Key parameters

| Parameter | Default | Description |
|---|---|---|
| `--input_dir` | *required* | Directory containing .tif / .tiff / .ome.tiff files |
| `--outdir` | `results` | Output directory |
| `--method` | `itkwasm_gaussian` | Downsampling method |
| `--ome_zarr_version` | `0.5` | OME-Zarr spec version (0.4 or 0.5) |
| `--chunks` | auto | Chunk size(s), e.g. `64` or `1 64 64` |
| `--chunks_per_shard` | none | Zarr v3 sharding (e.g. `4`) |
| `--codec` | default | Compression codec, e.g. `blosc:zstd` |
| `--compression_level` | default | Codec-specific level |
| `--series` | all | Series index or glob for multi-series TIFF |
| `--memory_target` | auto | ngff-zarr memory budget, e.g. `32GB` |
| `--cache_dir` | none | Disk cache path for very large datasets |
| `--use_tensorstore` | `false` | TensorStore I/O backend |
| `--dims` | auto | Override dimension labels, e.g. `c z y x` |
| `--scale` | auto | Override pixel spacing, e.g. `z 4.0 y 0.5 x 0.5` |
| `--units` | auto | Override units, e.g. `z micrometer y micrometer x micrometer` |
| `--no_omero` | `false` | Disable OMERO display metadata |
| `--omero_quantile_low` | `0.02` | Lower quantile for channel display window |
| `--omero_quantile_high` | `0.98` | Upper quantile for channel display window |

Full parameter reference: `nextflow_schema.json`

## Outputs

```
results/
  zarr/   *.ome.zarr   — converted OME-Zarr stores (one per input TIFF)
  logs/   *_convert.log — per-file conversion logs
```

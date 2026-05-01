# convert_tiff_to_zarr

Parallelisable Nextflow pipeline that converts large multi-channel TIFF images
to OME-Zarr using [ngff-zarr](https://github.com/thewtex/ngff-zarr).  
Each TIFF file is processed as an independent job, making the pipeline
trivially parallel on an HPC SLURM cluster.

## Requirements

- Nextflow ≥ 24.04
- One of: conda, Docker, Singularity/Apptainer, or a pre-installed `ngff-zarr`

## Quick start

```bash
# Local run, conda environment auto-created
nextflow run main.nf \
  -profile conda \
  --input '/data/images/*.tiff' \
  --outdir results

# SLURM cluster, singularity container (build first — see below)
nextflow run main.nf \
  -profile small,singularity \
  --input '/hpc/data/*.ome.tiff' \
  --outdir /hpc/results \
  --memory_target 64GB
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
| `--input` | *required* | Glob for input TIFF files |
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
  zarr/   *.ome.zarr   — converted OME-Zarr stores
  logs/   *_convert.log — per-file conversion logs
```

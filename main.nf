nextflow.enable.dsl = 2

// ---------------------------------------------------------------------------
// Input / output
// ---------------------------------------------------------------------------
params.input_dir        = null   // directory containing .tif / .tiff / .ome.tiff images
params.outdir           = "results"
params.publish_dir_mode = "copy"
params.validate_params  = true

// ---------------------------------------------------------------------------
// ngff-zarr: downsampling & format
// ---------------------------------------------------------------------------
params.method           = "itkwasm_gaussian"  // see: ngff-zarr --help
params.ome_zarr_version = "0.5"               // "0.4" or "0.5"
params.chunks           = null                // e.g. "64"  or  "8 16 32"
params.chunks_per_shard = null                // e.g. "4"   or  "2 4 8"
params.codec            = null                // e.g. "blosc:zstd", "gzip", "zstd"
params.compression_level = null              // e.g. 5

// ---------------------------------------------------------------------------
// ngff-zarr: series selection  (for multi-series OME-TIFFs)
// ---------------------------------------------------------------------------
params.series           = null  // int index (0), glob name ("*GFP*"), or null = all

// ---------------------------------------------------------------------------
// ngff-zarr: resource hints
// ---------------------------------------------------------------------------
params.memory_target    = null   // e.g. "32GB"  — passed to ngff-zarr, not Nextflow
params.cache_dir        = null   // path for disk caching very large datasets; defaults to <outdir>/cache
params.use_tensorstore  = false  // use TensorStore I/O backend

// ---------------------------------------------------------------------------
// ngff-zarr: metadata overrides (space-separated dim-value pairs)
// ---------------------------------------------------------------------------
params.dims             = null   // e.g. "c z y x"
params.scale            = null   // e.g. "z 4.0 y 1.0 x 1.0"
params.units            = null   // e.g. "z micrometer y micrometer x micrometer"
params.name             = null   // image name to embed in OME-Zarr metadata

// ---------------------------------------------------------------------------
// ngff-zarr: OMERO visualization metadata
// ---------------------------------------------------------------------------
params.no_omero              = false
params.omero_quantile_low    = 0.02
params.omero_quantile_high   = 0.98

// ---------------------------------------------------------------------------
// Process
// ---------------------------------------------------------------------------
process CONVERT_TIFF_TO_ZARR {
    tag { tiff_file.name }
    label 'process_medium'

    publishDir "${params.outdir}/zarr", mode: params.publish_dir_mode, saveAs: { new File(it).name }
    publishDir "${params.outdir}/logs", mode: params.publish_dir_mode

    input:
    path tiff_file

    output:
    path "*.ome.zarr", emit: zarr_stores
    path "*.log",      emit: logs

    script:
    // Strip common TIFF extensions to derive a clean output basename
    def base = tiff_file.name.replaceAll(/(?i)\.(ome\.)?(tiff?)$/, '')

    // ngff-zarr reads dask 'temporary-directory' config for its cache store;
    // set via env var to avoid the --cache-dir CLI bug (Path.makedirs AttributeError)
    def dask_tmp = params.cache_dir ? params.cache_dir.toString() : "${params.outdir}/cache"

    // Build optional argument list — null entries are filtered before joining
    def opt_args = [
        params.chunks
            ? "--chunks ${params.chunks}"
            : null,
        params.chunks_per_shard
            ? "--chunks-per-shard ${params.chunks_per_shard}"
            : null,
        (params.series != null)
            ? "--series ${params.series}"
            : null,
        params.memory_target
            ? "--memory-target ${params.memory_target}"
            : null,
        params.codec
            ? "--codec ${params.codec}"
            : null,
        (params.compression_level != null)
            ? "--compression-level ${params.compression_level}"
            : null,
        params.use_tensorstore
            ? "--use-tensorstore"
            : null,
        params.dims
            ? "--dims ${params.dims}"
            : null,
        params.scale
            ? "--scale ${params.scale}"
            : null,
        params.units
            ? "--units ${params.units}"
            : null,
        params.name
            ? "--name ${params.name}"
            : null,
        params.no_omero
            ? "--no-omero"
            : "--omero-quantiles ${params.omero_quantile_low} ${params.omero_quantile_high}",
    ].findAll { it != null }.join(" ")

    """
    set -euo pipefail

    # Route ngff-zarr disk cache to imaging storage, not scratch
    export DASK_TEMPORARY_DIRECTORY="${dask_tmp}"
    mkdir -p "${dask_tmp}"

    if ! command -v ngff-zarr &>/dev/null; then
        echo "ERROR: ngff-zarr is not available in PATH" >&2
        exit 1
    fi

    ngff-zarr \\
        -i "${tiff_file}" \\
        -o "${base}.ome.zarr" \\
        --method ${params.method} \\
        --ome-zarr-version ${params.ome_zarr_version} \\
        --quiet \\
        ${opt_args} \\
        2>&1 | tee "${base}_convert.log"
    """
}

// ---------------------------------------------------------------------------
// Workflow
// ---------------------------------------------------------------------------
workflow {
    if (!params.input_dir) {
        error(
            "Missing required parameter: --input_dir\n" +
            "Provide the path to a directory containing .tif / .tiff / .ome.tiff files, e.g.:\n" +
            "  nextflow run main.nf --input_dir '/data/images' --outdir results"
        )
    }

    if (params.omero_quantile_low < 0 || params.omero_quantile_low > 1) {
        error "omero_quantile_low must be between 0 and 1, got: ${params.omero_quantile_low}"
    }
    if (params.omero_quantile_high < 0 || params.omero_quantile_high > 1) {
        error "omero_quantile_high must be between 0 and 1, got: ${params.omero_quantile_high}"
    }
    if (params.omero_quantile_low >= params.omero_quantile_high) {
        error "omero_quantile_low must be less than omero_quantile_high"
    }

    // Collect .tif and .tiff (covers plain TIFF and OME-TIFF with both extensions)
    def inDir = params.input_dir.toString().replaceAll(/\/$/, '')
    Channel
        .fromPath(["${inDir}/*.tif", "${inDir}/*.tiff"], checkIfExists: false)
        .ifEmpty { error("No .tif or .tiff files found in directory: ${params.input_dir}") }
        | CONVERT_TIFF_TO_ZARR

    CONVERT_TIFF_TO_ZARR.out.zarr_stores
        .flatten()
        .view { store -> "Converted: ${store.name}" }
}

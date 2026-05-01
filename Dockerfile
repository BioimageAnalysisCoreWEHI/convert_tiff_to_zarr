FROM python:3.12-slim

LABEL maintainer="WEHI SODA Hub"
LABEL description="ngff-zarr: convert TIFF images to OME-Zarr"

RUN apt-get update && apt-get install -y --no-install-recommends \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "ngff-zarr[cli]"

ENTRYPOINT ["ngff-zarr"]

---
title: Persistent State, Volumes, and Resources
---

# Persistent State, Volumes, and Resources

A machine combines managed guest state with resources and optional host integrations. Their lifetimes differ.

## Machine state

A persistent machine keeps changes to its managed disk across stop and start operations. Package installations, generated files, and other disk writes remain until the machine is deleted or the state is otherwise replaced.

Not every guest path is on that disk. Memory-backed paths such as `/tmp`, `/run`, and `/dev/shm` hold their contents while the machine runs and are empty again after a stop and start. Write files that must outlive a restart to `/workspace` or another path on the machine filesystem. See [Cloud Lifecycle, Storage, and Networking](/docs/cloud/lifecycle-storage-networking) for the full breakdown.

An ephemeral run is cleaned up when it exits. Use a persistent machine, a pack, a volume, or external storage when data must outlive that run.

## Volumes and mounts

A volume maps storage into the guest. It can come from two places.

A host-directory mount shares a selected host path with the machine and therefore crosses the VM isolation boundary.

A remote volume mounts S3-compatible object storage instead, using the same flag with an `s3://` source. The bucket is mounted inside the guest by the machine's agent, which speaks the S3 API and FUSE directly, so the image needs nothing installed: no rclone, no fuse3, not even a shell. A bucket can therefore be mounted into a distroless or scratch image. The mount is in place before the workload's first instruction runs, and it is re-established on every start.

Credentials come from the machine's own environment: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, with `AWS_ENDPOINT_URL` for S3-compatible services such as R2 or MinIO and `AWS_REGION` where it matters. Without them the bucket is read anonymously, which covers public datasets.

Volumes are runtime attachments. A `.smolmachine` artifact does not make its external volume bindings portable or persistent. Re-specify the required volumes each time a packed artifact runs.

For Docker inside a machine, place Docker data on the machine's ext4 storage disk, such as `/storage/docker`. Docker's `overlay2` driver cannot nest on the overlay-backed root filesystem.

## CPU and memory

CPU and memory are assigned when the machine is configured. The local CLI defaults are 4 vCPUs and 8 GiB of memory when no Smolfile overrides them. Smolfile defaults may differ, so set values explicitly when reproducibility matters.

Memory uses virtio ballooning. The configured amount is the guest-visible capacity; the host can reclaim unused guest memory. A high configured limit does not mean the host permanently commits that full amount.

Available cloud sizes and limits are service-specific. Do not infer hosted limits from local defaults.

## Architecture and portability

Machine artifacts are architecture-specific. An arm64 artifact cannot be restored as an x86_64 machine, or the reverse. Host support also depends on the required hypervisor and optional GPU features.

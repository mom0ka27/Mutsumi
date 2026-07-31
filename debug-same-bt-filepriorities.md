# Debug Session: same-bt-filepriorities

Status: [OPEN]

## Symptom

Investigate why `filePriorities` fails when the same BT is downloaded concurrently or added repeatedly through the server qBittorrent torrents/download implementation.

## Hypotheses

1. Concurrent requests resolve the same torrent to an incomplete or stale torrent identifier before qBittorrent has finished registering it.
2. Duplicate-add handling treats qBittorrent's duplicate response as a new torrent and calls `filePriorities` with an invalid or missing hash.
3. `filePriorities` is called before the torrent metadata/files are available, causing a timing or eventual-consistency failure.
4. The request uses an incorrect hash or file-priority payload shape under concurrent code paths.
5. Parallel priority updates race with torrent deletion/replacement or with another priority update.

## Evidence

Not collected yet.

## Changes

Not started.

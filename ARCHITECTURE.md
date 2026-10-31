# Architecture

## Boundaries

`StorageCore` is UI-independent. `FileSystemScanner` performs a bounded, depth-first traversal on a detached user-initiated task. It calls `lstat` once per visited item, never reads file contents, never follows a symbolic link, stays on the root device by default, and checks cooperative cancellation throughout. It publishes counters every configurable batch and a partial root after each top-level branch.

The traversal retains one `FileNode` per visible filesystem entry because the expandable hierarchy requires it. It does not create a task per entry and directory enumeration is scoped to one directory at a time. Memory is therefore proportional to displayed metadata, not file contents or outstanding concurrency. Very large single directories are still returned by Foundation as one URL array; replacing this with a POSIX streaming directory iterator is a possible phase-two optimization.

`ScanCoordinator` is isolated to the main actor. It owns display state, scan generations, cancellation, selected IDs, and security-scoped access lifetimes. Worker callbacks hop to the main actor in batches. Scan generation IDs prevent stale cancelled scans from overwriting newer results.

`DeletionPolicy` is the central safety gate. The UI consults it when selecting, the review view normalizes selections, and `TrashService` invokes it again immediately before each operation. Revalidation checks existence, scope containment, protected locations, writability, and the scanned `(device, inode)` identity. This limits path-swap races; if identity cannot match, the operation is refused. `TrashService` only calls `FileManager.trashItem` and returns one result per approved target.

`VolumeInfoProvider` uses Foundation capacity resource values. Its values are presented as authoritative volume metrics, separately from accessible scan aggregation.

After a successful Trash operation, `FileTreeUpdater` removes the known paths from the existing snapshot and recomputes their ancestor aggregates without walking the filesystem again. If the counted entry of a hard-linked file was moved, another visible link is promoted to retain that identity's size contribution. Only the inexpensive volume-capacity resource values are queried again; users can still request a manual rescan when external filesystem changes are suspected.

## Accounting

Regular-file logical size is `st_size`; allocated size is `st_blocks × 512`, matching Darwin's documented block unit. The scanner aggregates children bottom-up. The first regular file seen for a `(st_dev, st_ino)` identity contributes size and count; later hard links remain visible but contribute zero and carry a duplicate marker. Symlinks contribute only their link metadata and are leaf nodes.

Directories with any denied or skipped descendants remain useful partial results, and the snapshot becomes `Incomplete`. Cancellation preserves the last completed branches and marks the final snapshot `Cancelled`.

## Deletion threat model

Protected paths include system roots, all volume roots, the user's home root, the running bundle, and wholesale application/developer category roots. A candidate must be strictly below the active root. The policy uses standardized absolute paths for containment and `lstat` for identity so a symlink is validated as the link rather than its destination. No privilege escalation, shell command, automatic recommendation, background cleanup, empty-Trash, or permanent deletion exists.

There is an unavoidable interval between final `lstat` and `trashItem`. Foundation does not expose an inode-bound Trash API, so a hostile process with write access to the parent directory could theoretically race that final call. The app minimizes the interval and fails closed on detected changes; stronger descriptor-relative mutation is not available through Finder Trash semantics.

## Distribution

The MVP is intentionally unsandboxed and locally signed because broad storage inspection and App Sandbox user-selected access have different scopes. It still honors TCC and ordinary permissions. Production distribution should use Developer ID signing, hardened runtime, notarization, and stapling without adding network, login-item, or unnecessary entitlements.

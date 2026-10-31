# Mac Storage Inspector

Mac Storage Inspector is a native macOS 14+ utility for understanding accessible disk usage and explicitly moving reviewed items to Finder Trash. Scans stay on the Mac, read metadata only, do not follow symlinks or other mounted filesystems, and never automatically or permanently delete anything.

## Build and run

The easiest development workflow is to install current Xcode, open `Package.swift`, select the `MacStorageInspector` executable scheme, and Run. The project has no third-party dependencies or network access.

From Terminal with a matching Apple toolchain:

```sh
swift build
swift test
swift run MacStorageInspector
```

Create a locally signed application bundle:

```sh
./Scripts/build-app.sh
open "dist/Mac Storage Inspector.app"
```

The generated app uses ad-hoc signing and is intended for local development. A distributed release should use a Developer ID Application certificate, hardened runtime, an archive submitted to Apple's notarization service, and stapling. No App Sandbox entitlement is enabled in the MVP: this is intentional for a directly distributed storage scanner. TCC and filesystem permissions still apply.

This machine currently has Command Line Tools 16.0 but no full Xcode. Its default macOS 15.0 SDK and Swift compiler builds are mismatched; the scripts select its compatible macOS 14.5 SDK. The CLT installation also lacks the XCTest platform path, so `Scripts/test.sh` runs the standalone fixture-based integration checks. With full Xcode it runs the Swift Testing suite.

## Use

1. Choose **Scan Home**, **Choose Folder**, or the advanced **Scan Data Volume** option.
2. Browse results as top-level branches finish. Allocated and logical sizes remain separate.
3. Inspect an item's full path, warning category, and metadata. Reveal it in Finder if uncertain.
4. Explicitly select items, review the normalized top-level list and full paths, then confirm **Move to Trash**. Risky Library, application, developer, and package paths require an additional acknowledgement.
5. Review individual successes and failures. Successful items are removed from the current results and ancestor totals are recomputed in memory; only volume-capacity metadata is refreshed.

No item is preselected. Finder Trash is reversible, and moving an item there does not immediately increase available space. The app does not empty Trash.

## Permissions

Folder selection uses a security-scoped URL while that scan is active. Home and Data-volume scans may encounter TCC-protected locations. Those failures appear in **Scan Issues** and do not abort accessible branches.

For broader directly distributed scans, add **Mac Storage Inspector** under **System Settings → Privacy & Security → Full Disk Access**, quit the app, and reopen it. Full Disk Access does not override every permission, and the app never requests a password or invokes `sudo`.

## Measurement and APFS limitations

- File identity and sizes come from `lstat`: logical bytes are `st_size`; allocated bytes are `st_blocks × 512`.
- Directory values are bottom-up sums, never directory resource-value guesses.
- Hard links are counted once per `(device, inode)` during a scan. APFS clones cannot be reliably deduplicated by public file metadata and may overstate aggregate physical use.
- Sparse files correctly show separate logical and allocated values.
- Volume capacity is reported separately from accessible scanned bytes. APFS shared containers, purgeable space, snapshots, filesystem metadata, inaccessible paths, and Trash mean the values will not reconcile exactly.
- Online-only cloud metadata is inspected without intentionally reading or hydrating contents, but provider behavior remains outside the app's control.
- Package bundles are scanned for analysis but treated as advanced items during Trash review.

## Tests

```sh
./Scripts/test.sh
```

The fixture suite covers bottom-up aggregation and ranking, hard links, sparse files, symlink loops, exclusions, Unicode/whitespace paths, cancellation, protected roots, identity revalidation, and nested selection. Fixtures live only in a unique temporary directory. The test runner never trashes or touches real user files.

## Safety guarantees

- Native `FileManager.trashItem` is the only production mutation API.
- Protected system roots, volume roots, the home root, the running app, and protected category roots cannot be selected.
- Every target must be a writable descendant of the active scan scope and is revalidated by canonical path and `(device, inode)` immediately before trashing.
- Symlinks are represented as leaf entries and never traversed.
- Nested selections collapse to top-level targets, preventing duplicate operations or accounting.
- Failures are reported per item and never trigger automatic retries or a permanent-delete fallback.

See [ARCHITECTURE.md](ARCHITECTURE.md) for implementation details and trade-offs.

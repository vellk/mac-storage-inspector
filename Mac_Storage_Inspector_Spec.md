# Mac Storage Inspector - Technical Specification

**Status:** Implementation-ready MVP specification  
**Target:** Codex or Claude Code  
**Language:** Swift  
**UI:** SwiftUI (AppKit integration where necessary)  
**Platform:** macOS 14+ (validate SDK compatibility on installed Xcode)  
**Distribution (MVP):** locally built `.app`, outside Mac App Store  
**Core principle:** user-controlled, read-only scanning, explicit deletion to Trash only.

## 1. Product goal

Build a small, fast, privacy-first macOS disk space analyzer. Users should quickly identify the largest directories and files, understand what they contain, inspect them in Finder, and manually select items to move to Trash.

The app **must not** perform automatic cleanup, infer that a cache is safe to remove, delete without confirmation, or permanently delete files. It must not upload filesystem information.

### Primary user journey

1. Open application and select **Scan Home** (default), **Choose Folder**, or **Scan Data Volume** (advanced).
2. See used/free storage summary and continuously updated results while scanning.
3. Explore largest directories ordered by descending size; expand into subdirectories and see individual large files.
4. Select a target, inspect its absolute path, physical/logical size, content and risk hint; optionally reveal it in Finder.
5. Mark one or several eligible items. Review the exact target list, item count and *estimated* allocated size.
6. Confirm **Move to Trash**, with an additional confirmation for app data and developer folders.
7. Show individual successes and failures; refresh changed branches and free-space metrics. Explain that actual free disk space may not increase until Trash is emptied and APFS snapshots are released.

## 2. Explicit scope

### MVP includes

- Native macOS app, unified window with sidebar and directory detail area.
- Recursive scan of one selected root, initially current user's home directory.
- Optional manual scan of `/System/Volumes/Data` with read-access caveats.
- Summary: volume total, available capacity, scanned accessible allocated size, inaccessible/error count. Clearly distinguish these metrics.
- Hierarchical table/tree with folder name, full path, allocated size, logical size if available, file counts, percent of scanned root; sorting descending by allocated size.
- Largest files view (top 100) and largest directories view (top 100), non-duplicative and drill-down friendly.
- Selection via checkboxes; no initial preselection.
- Show details: path, size, count, modified date if available, directory/application identifier if recognized, reason for caution and permission errors.
- Reveal in Finder, copy path, rescan selected subtree, pause/cancel scan.
- Move explicitly selected, eligible files/folders to Trash, not permanent deletion.
- Clear progress indication (files scanned, bytes aggregated, current path, partial results) and partial success on unreadable paths.
- Basic exclusion settings (user-chosen paths; default exclusions only for recursion hazards and inaccessible OS internals).
- Display any errors, permission issues, and skipped locations; never silently claim complete coverage.
- Basic light/dark mode, accessibility labels, keyboard navigation and responsive window layouts.
- Unit tests and a small integration test fixture.

### Out of scope for MVP

- Automatic cleaning, scheduled jobs, background daemon or startup task.
- Root/sudo execution, privilege escalation, SIP bypass or manipulation of macOS protected data.
- Empty Trash, permanent deletion, deletion of APFS snapshots or Time Machine data.
- Duplicate finding by file content or sophisticated APFS clone accounting.
- Container image, database or cache-specific automatic cleanup (Docker/OrbStack/JetBrains/etc.).
- Cloud sync, telemetry, network requests, accounts, or analytics.
- Treemap visualization and scan history/diff (phase 2).

## 3. User experience and layout

### Main window

- **Top bar**: selected volume/root, Scan/Cancel/Rescan buttons, Settings and Scan status.
- **Capacity summary**: volume total, used, available; separate label for scanned accessible bytes. Do not display scanned file totals as the authoritative APFS used capacity.
- **Navigation/sidebar**: Home, selected folders, Largest Directories, Largest Files, Scan Issues. Optional category shortcuts based strictly on paths (Caches, Developer Tools, Containers, Downloads).
- **Main content**: outline/table hierarchical browsing, Name, Allocated, Logical, Share %, Items; sorted by allocated descending by default. Use proportional inline bars.
- **Details pane**: full canonical path, permissions, file information, size and status; buttons `Reveal in Finder`, `Copy Path`, `Rescan`, `Select for Trash` where allowed.
- **Bottom selection bar**: number selected, estimated allocated size, `Review Selection` action.

### Deletion review

- List all selected *top-level* items with full paths, sizes and risk indicators.
- Collapse nested selections: if a parent is selected, prevent duplicate selection/accounting of its descendants.
- Label that moving to Trash is reversible through Finder and **does not immediately free disk space**.
- Show strong warnings for app data, developer tools, home subdirectories or potential active application storage.
- No prechecked items; explicit user confirmation required per batch.
- Offer `Cancel` and `Move N Items to Trash` actions; report partial failures rather than retrying destructive operations automatically.
- No `rm -rf`, `FileManager.removeItem`, shell deletion commands or empty-trash functionality.

## 4. Safety rules - non-negotiable

- Deny deletion of `/`, `/System`, `/System/Volumes`, `/System/Volumes/Data`, `/Applications`, `/Library`, `/private`, `/usr`, `/bin`, `/sbin`, `/dev`, `/Volumes`, any filesystem volume root, the user's home directory itself, and the current app bundle or its executable path. Also deny deletion of any ancestor of a protected root.
- Deny moves to Trash for paths outside explicitly granted, writable and user-selected scope; if the process lacks permission, show the error rather than escalating privileges.
- Default to caution for `~/Library`, `~/Library/Containers`, `~/Library/Group Containers`, `~/Library/Application Support`, `~/.docker`, `~/.orbstack` and `.git`. They may be scanned but **not treated as caches**. Require additional warning for their children. The app never deletes the protected category roots wholesale in MVP.
- Revalidate target on deletion (exists, type, identity if available, real/canonical path, writable scope). Detect a swapped path or symlink race and refuse when validation cannot be established. A symbolic link must never cause deletion of its target.
- Do not traverse symlinks or Finder aliases as directories. Show symlinks as entries with their own metadata.
- Do not follow mounts into other filesystems by default; allow separately scanning a selected volume.
- Avoid double-counting hard-linked files by `(volume ID, file ID/inode)` during each scan. Make clear that APFS clones can still cause aggregate allocated-byte overestimation.
- Recognize package bundles (e.g., `.app`, `.photoslibrary`) and allow inspection, but treat as a single protected/advanced item for deletion UX, and do not classify as ordinary caches.
- No recommendation like “safe to delete” without reliable ownership and a documented rule; prefer `Unknown`, `Likely regenerable`, `Potentially valuable data`, `System-protected` with clear explanation. **All classifications are advisory.**
- Never run arbitrary shell commands with user paths. File operations must use native Foundation APIs, correctly handling spaces, Unicode and other special characters.
- Do not read file contents; use only directory entries and filesystem metadata.

## 5. File scanning behavior

### Implementation

- Use `FileManager`, `URLResourceValues` and (if needed) POSIX `lstat`/`statfs` for identity and allocated-block information. Evaluate `fileAllocatedSizeKey`, `totalFileAllocatedSizeKey`, `fileSizeKey` and volume capacity keys; choose and document consistent accounting. Where a key is unavailable, fall back to POSIX allocated blocks with explicit uncertainty.
- Directory size is aggregated bottom-up. Store `logicalBytes` and `allocatedBytes` separately. Do **not** treat a directory resource value as the recursive sum of descendants.
- Scan should be interruptible using Swift concurrency cancellation, with bounded work queues so a large directory cannot exhaust memory.
- Use `URLResourceValues` and native enumeration; don't shell out to `du` for core scanning.
- Maintain a stable tree keyed by canonical resource identity/path, with an aggregate per directory, and stream batched updates to the UI on the main actor.
- Handle protected areas, TCC denial, unreadable folders, broken links, sparse files, APFS clones, hard links, hidden files and package directories.
- By default do not cross filesystem boundaries. Display skipped and inaccessible counts.
- Allow normal files in cloud-backed folders to be scanned by metadata without triggering download where possible; never intentionally hydrate an online-only file. Mark uncertain sizes.
- Never block UI while scanning; cancel promptly and preserve partial results labeled `Incomplete`.
- Display actual scan duration and work progress; when denominator unknown, use an indeterminate progress indicator plus counters.

### Disk-space accuracy

- Get volume used/free/total via appropriate volume capacity APIs or `statfs` and clearly label what is reported. Explain that macOS APFS uses a shared container, snapshots, purgeable files, sparse files and clone sharing.
- The tree shows the sum of **accessible files scanned**, not necessarily the physically occupied space of an APFS container.
- Avoid claiming that a sum of top-level `du` values accounts for all bytes; unreadable paths and APFS overhead/snapshots remain unaccounted for.
- For large sparse VM images such as `Docker.raw`, show `Logical size` and `Allocated size` side by side, highlighting that they can differ substantially.
- If snapshots are ever displayed (phase 2), do so as separate read-only data and never assign snapshot space to arbitrary visible folders.

## 6. macOS permissions and distribution

- MVP distribution outside the Mac App Store, locally built `.app`, with a documented signing/notarization plan for releases.
- Prefer an initial user-selected root using macOS file selection. For a sandboxed implementation, use a security-scoped folder URL and bookmarks for persistent access; ensure `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` are paired.
- Do not assume `Full Disk Access` bypasses App Sandbox restrictions. Choose and document an intentional sandbox strategy: for broader home/data volume scanning in a directly distributed app, assess an unsandboxed signed build, while still respecting TCC protections and user-granted Full Disk Access where needed.
- Never prompt for a user password or launch shell commands via `sudo`.
- On permission denial, provide concise instructions to grant access in macOS Settings and a `Retry` button. Scanning must remain useful with partial access.
- Do not add unnecessary entitlements, network connections, background services or login items.

## 7. Data models and service boundaries

Suggested modules/protocols (agent may refine names while retaining boundaries):

- `FileSystemScanner`: async recursive scan, incremental events, cancellation.
- `DiskUsageSnapshot`: scan root, start/end time, completeness state, volume capacity, nodes, skipped paths and errors.
- `FileNode`: id, URL, name, type, file ID, volume ID, parent, children, logical bytes, allocated bytes, file count, warning category, permissions/scan status.
- `ScanCoordinator`: drives scan state, sorting, filtering and selection.
- `TrashService`: validates and moves approved files to Trash; independently testable protocol.
- `DeletionPolicy`: protected roots, nested-selection normalization, risk warnings, revalidation.
- `VolumeInfoProvider`: capacity and mounted volume information.
- `SettingsStore`: user preferences and excluded folders, stored locally.

Use native `FileManager.trashItem(at:resultingItemURL:)` for a user-confirmed move to Trash. Never substitute permanent deletion if trashing is unsupported or fails.

## 8. Performance and quality requirements

- Scanning must not freeze the main thread; the results list must stay interactive during scans.
- Show first visible results incrementally instead of waiting until the entire tree is complete.
- Aim for memory bounded by relevant metadata, not loaded file contents; document any throughput assumptions, don't promise fixed times for arbitrary disk sizes.
- Handle directory trees with hundreds of thousands or millions of entries without unbounded task spawning.
- Preserve sorting, selection and expanded tree state where possible after partial refresh.
- Test macOS 14+ with latest available Xcode in development environment; verify current compiler and SDK rather than assuming APIs exist.

## 9. Acceptance criteria

1. Launch app; select Home; scan works without Terminal, and no network request is needed.
2. Results list accurately ranks intentionally created 1 GB / 2 GB / 3 GB test directories by allocated bytes (allowing filesystem metadata differences).
3. Users can drill down to a specific file, reveal it in Finder and copy its exact path.
4. Permission-denied paths are reported, not silently assumed empty.
5. Symlink loops terminate and do not scan outside selected root.
6. Hard-linked test files are not counted twice in the aggregate for a single volume; behavior for APFS clones is documented.
7. Sparse file shows differing logical and allocated sizes when appropriate.
8. Scan can be cancelled; UI stays responsive, results are marked incomplete.
9. Selection has no default items; nested selected parent/child are not double-counted.
10. Protected directory or ancestor cannot be deleted, even via drag/drop, direct model state changes or a forged path.
11. Confirmation shows explicit full paths; cancel causes no modifications.
12. Only confirmed items are moved to Finder Trash with native APIs; no permanent deletion.
13. Partial Trash errors are shown per item and do not cause unapproved retries.
14. A refresh reflects moved items and separately recomputes actual available volume space.
15. Unit/integration tests pass for size aggregation, hard links, sparse files, symlinks, denied access, path validation and Trash service using temporary fixtures.
16. README documents build, required permissions, known APFS limitations and installation.

## 10. Test strategy

- Unit tests: aggregation, sorting, percent calculation, protection policy, nested selection, path normalization and warning labels.
- Integration tests (temporary fixtures only): nested trees, files >1 GiB (sparse fixtures for size semantics), hard links, symlinks, inaccessible directories where reproducible, filename whitespace/non-ASCII, cancellation and partial result recovery.
- Trash service: mock for unit tests; opt-in integration test using only test-created items and explicit cleanup instructions.
- Manual validation: scan a development Mac with large `~/Library/Caches`, `~/Library/Application Support`, `~/Library/Containers` and `~/Library/Group Containers`; no changes until explicit confirmation.
- Verify no operations touch external files or real user files in automated tests.

## 11. Recommended implementation sequence for coding agent

### Phase A - Foundation and scanner

1. Create Xcode SwiftUI macOS project with clear target settings, tests and README.
2. Define models, capacity provider, scanner protocol and tests.
3. Implement recursive asynchronous traversal, volume boundary handling, hard-link tracking, logical/allocated sizes and errors.
4. Add cancellation, incremental progress and tests with synthetic fixtures.

### Phase B - Usable analysis UI

5. Implement disk summary, directory outline, sorting, top directories/files and details pane.
6. Add Finder reveal, copy path, path selection, exclusions, permission guidance.
7. Validate navigation with large test fixture; add accessibility features.

### Phase C - Safe manual deletion

8. Implement protected-path policy and selection normalization, with tests.
9. Implement confirmation review and native Trash service with per-item error reporting.
10. Add refresh after operations; verify none of the core workflows calls permanent deletion.

### Phase D - Packaging

11. Run formatter/linter if adopted, tests and build in Debug and Release configurations.
12. Produce a runnable `.app`, document manual installation and Full Disk Access workflow when needed.
13. Verify documented steps on a clean test user; enumerate known limitations.

## 12. Deliverables

- Complete buildable Xcode project and source code.
- Test suite and passing test report.
- `.app` release build (if build tools available in agent environment).
- README: setup, permissions, build instructions, use, safety model, APFS limitations.
- Architecture note describing scan performance, measurement method, deletion safeguards and known trade-offs.
- No bundled third-party binaries unless explicitly approved and license documented.

## 13. Instructions to Codex / Claude Code

Implement the MVP described here, not a prototype screenshot. First inspect the installed Xcode, macOS SDK and project state. Produce a short architecture plan, then implement incrementally with runnable tests. Prefer simple Apple-native APIs and no external dependencies. Prioritize accurate size analysis, safe filesystem boundaries and an attractive but straightforward SwiftUI UI. Do not use shell deletion or include auto-cleanup behavior. After each milestone build and run the relevant tests; at the end provide exact local build/run instructions and a concise list of known limitations. If an API behavior is uncertain, check the installed SDK and Apple's docs and add a targeted test rather than guessing.

## 14. Official API references

- Foundation `URLResourceKey`: https://developer.apple.com/documentation/foundation/urlresourcekey
- Foundation `FileManager.trashItem(at:resultingItemURL:)`: https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)
- SwiftUI file importer (security-scoped URLs): https://developer.apple.com/documentation/swiftui/view/fileimporter(isPresented:allowedContentTypes:onCompletion:)
- Apple App Sandbox access: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox

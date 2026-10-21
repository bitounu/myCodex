# Update and rollback safety review

The review found and corrected filesystem defects in the implementation tagged
`v2026.10.1`. The tests provide evidence for the cases below; they are not a proof
that every possible execution is bug free. The existing tag was not changed.

## Defects reproduced and corrected

| Case | Previous behavior | Corrected behavior |
| --- | --- | --- |
| Installation or bundle lock linked to another file | Opening the lock with `>` truncated the linked file, including hardlinks. | Symlinks are rejected. Locks are opened without truncation; hardlinked file contents are preserved. |
| Metadata destination unexpectedly becomes a directory | `mv` placed a file inside that directory. | An exact destination is required; unexpected directories are refused. |
| Executable destination becomes a directory at the final rename | `mv` could overwrite a same-named file inside that directory. | The rename refuses directory-target semantics. The test directory and its contents remain intact. |
| Application storage contains directory symlinks | Writes could follow them into unrelated folders. | Canonical, owned ordinary directories are required under the configured storage roots. |
| Destination parent is renamed and replaced with a symlink during activation | A path-based move could be redirected into another folder. | The move holds the verified destination directory as its working directory. |
| Atomic rename is unavailable across filesystems | Generic `mv` could fall back to copying and deleting its source. | `--no-copy` refuses the operation and preserves both source and destination. |
| Executable activation fails | The highest-installed-version record had already advanced. | History advances after successful activation. A later operation recovers an interrupted history write from the active, verified executable. |

The same replacement helper is used by installation, update, rollback,
background check metadata, and bundle extraction. Initial installation and new
receipt directories use a no-clobber rename. Existing metadata is replaced using
fresh temporary files, rather than opening existing paths for writing.

## Verification

Run the release tests separately from publication:

```bash
python3 tests/release_test.py
```

All 36 release tests passed on the review host, with no skips, including the
compatibility test using the original `v2026.10.1` source. They use real generated
SSH keys, signed bundles, and isolated installations; GitHub transport is
simulated. Test artifacts are retained.

Coverage includes:

- Signed installation, update, rollback, and rollback in both directions.
- Updating an old implementation, rolling back to it, and updating again.
- Reproducible builds; signature, manifest, and payload corruption rejection.
- Failed downloads, failed activation, failed rollback, and interrupted history
  writes, with retries and preservation of the usable installed executable.
- Development symlinks, Git worktrees, unregistered and modified executables,
  installation locks, application-directory symlinks, metadata symlinks, lock
  symlinks and hardlinks, and directory collisions.
- Destination directory and parent-directory swaps injected at the final move.
- A real cross-filesystem move attempt between the test directory and `/dev/shm`.
- Preservation of unrelated file contents, symlinks, directory entries, and inodes.

On this Linux host, the test suite also traced real update and rollback processes
and their children using `strace -f -e trace=unlink,unlinkat,rmdir`. Neither
operation issued these deletion syscalls. Atomic renames still replace the
intended managed executable and metadata; the trace is not a claim that no files
change. The cross-filesystem and syscall tests explicitly skip when their host
requirements are unavailable. The historical compatibility test skips if the
old tag is unavailable locally.

ShellCheck and Bash syntax checks passed. Existing launcher configuration and
lifecycle tests passed, and the GPU suite passed with three optional Compose
schema tests skipped. The existing GUI suite's X11 socket-permission problem is
outside this audit and remains unresolved. Tests are not run by the publisher.

## Scope and limits

Normal writes are limited to the registered launcher, staging files beside it,
and the application's data, state, and cache directories. The release-management
and bootstrap code contain no removal commands or removal traps and do not prune
old releases. Explicit XDG
base directory settings are resolved before appending the `myCodex` namespace;
symlinks inside that namespace are refused. The installer resolves a deliberately
chosen `--bin-dir` before registering the executable.

The implementation requires GNU `mv` with `--no-copy` support, or a compatible
`gmv`. An unsupported host refuses the move instead of using a copy-and-delete
fallback. This review used GNU coreutils 9.4.

Locks serialize cooperating myCodex operations. They cannot stop another process
with write access from replacing the final filename between its last validation
and the rename. There is no atomic compare-and-swap of that filename and its
verified digest here. Arbitrary concurrent changes, a compromised account or
signing key, and filesystem/hardware failures are outside the assurance provided
by these tests. In particular, this is not an absolute promise that an unrelated
file inserted at the final filename during that race could never be replaced.

The fixes must ship in a new release. Updating source code does not change
already-downloaded bundles, and rolling back to an older release also restores
that release's older updater implementation.

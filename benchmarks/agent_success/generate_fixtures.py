#!/usr/bin/env python3
"""Generate or refresh agent-success benchmark task fixtures."""

from __future__ import annotations

import json
import os
import stat
import textwrap
from pathlib import Path
from typing import Any

BENCHMARK_ROOT = Path(__file__).resolve().parent
TASKS_DIR = BENCHMARK_ROOT / "tasks"

VERIFY_HEADER = """\
#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
"""

ADVERSARIAL_VERIFY_HEADER = """\
#!/usr/bin/env bash
# Auto-generated adversarial verify script — checks post-mutation workspace state.
set -euo pipefail

: "${WORKSPACE_ROOT:?WORKSPACE_ROOT is required}"

"""


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


WORKFLOW_SPECS: dict[str, dict[str, list[str]]] = {
    "literal_search_patch": {
        "expectedTools": ["search.literal", "file.stat", "patch.validate", "patch.apply"],
        "failureModes": ["search_empty", "patch_failed", "outside_workspace"],
    },
    "token_search_patch": {
        "expectedTools": ["search.tokens", "patch.validate", "patch.apply"],
        "failureModes": ["invalid_params", "patch_failed"],
    },
    "multi_file_patch": {
        "expectedTools": ["search.literal", "patch.validate", "patch.apply"],
        "failureModes": ["patch_failed", "stale_content"],
    },
    "multi_file_batch_patch": {
        "expectedTools": ["patch.validate", "patch.applyBatch"],
        "failureModes": ["patch_failed", "batch_partial_failure"],
    },
    "stale_content_recovery": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["stale_content", "patch_failed"],
    },
    "symlink_rejection": {
        "expectedTools": ["patch.apply", "file.stat", "patch.validate"],
        "failureModes": ["symlink_target", "permission_denied"],
    },
    "symlink_escape_read": {
        "expectedTools": ["file.stat", "patch.validate", "patch.apply"],
        "failureModes": ["symlink_escape", "outside_workspace"],
    },
    "large_file_shell_avoidance": {
        "expectedTools": ["shell.catSmall", "shell.sedRange", "patch.validate", "patch.apply"],
        "failureModes": ["shell_file_too_large", "shell_truncated", "partial_result"],
    },
    "large_file_read_avoidance": {
        "expectedTools": ["file.read", "shell.head", "patch.validate", "patch.apply"],
        "failureModes": ["partial_result", "shell_file_too_large"],
    },
    "shell_rg_sed_patch": {
        "expectedTools": ["shell.rg", "shell.sedRange", "patch.validate", "patch.apply"],
        "failureModes": ["shell_rg_failed", "patch_failed"],
    },
    "batch_rollback": {
        "expectedTools": ["patch.validate", "patch.applyBatch"],
        "failureModes": ["stale_content", "batch_rollback", "patch_failed"],
    },
    "batch_validation_rollback": {
        "expectedTools": ["patch.validate", "patch.applyBatch"],
        "failureModes": ["stale_content", "batch_rollback", "patch_failed"],
    },
    "semantic_recovery": {
        "expectedTools": ["search.semantic", "search.literal", "patch.validate", "patch.apply"],
        "failureModes": ["semantic_disabled", "search_empty"],
    },
    "semantic_paths_recovery": {
        "expectedTools": ["search.semantic", "search.paths", "search.literal", "patch.validate", "patch.apply"],
        "failureModes": ["semantic_disabled", "search_empty"],
    },
    "partial_search_pagination": {
        "expectedTools": ["search.literal", "patch.validate", "patch.apply"],
        "failureModes": ["results_truncated", "partial_result"],
    },
    "partial_grep_truncation": {
        "expectedTools": ["workspace.grep", "patch.validate", "patch.apply"],
        "failureModes": ["results_truncated", "partial_result"],
    },
    "verify_after_mutation": {
        "expectedTools": ["patch.validate", "patch.apply", "verify.status"],
        "failureModes": ["patch_failed", "verify_failed"],
    },
    "verify_after_mutation_batch": {
        "expectedTools": ["patch.validate", "patch.applyBatch", "verify.status"],
        "failureModes": ["patch_failed", "batch_partial_failure", "verify_failed"],
    },
    "adv_wrong_file_decoy": {
        "expectedTools": ["search.literal", "file.stat", "patch.validate", "patch.apply"],
        "failureModes": ["wrongFileEdited", "patch_failed"],
    },
    "adv_verify_only": {
        "expectedTools": ["file.read", "patch.validate", "patch.apply"],
        "failureModes": ["wrongFileEdited", "patch_failed"],
    },
    "adv_preserve_partial": {
        "expectedTools": ["file.read", "patch.validate", "patch.apply"],
        "failureModes": ["wrongFileEdited", "patch_failed"],
    },
    "adv_failed_patch_retry": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["patch_failed", "stale_content"],
    },
    "adv_multi_file_coord": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["wrongFileEdited", "patch_failed"],
    },
    "adv_stale_read": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["stale_content", "patch_failed"],
    },
    "adv_rollback_corruption": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["patch_failed", "rollback_required"],
    },
    "adv_noop_trap": {
        "expectedTools": ["shell.rg", "patch.validate", "patch.apply"],
        "failureModes": ["wrongFileEdited", "verify_failed"],
    },
    "adv_path_containment": {
        "expectedTools": ["file.stat", "patch.validate", "patch.apply"],
        "failureModes": ["outside_workspace", "wrongFileEdited"],
    },
    "adv_ambiguous_symbol": {
        "expectedTools": ["search.literal", "patch.validate", "patch.apply"],
        "failureModes": ["wrongFileEdited", "patch_failed"],
    },
    "night_spec_shadowing": {
        "expectedTools": ["search.literal", "file.read", "patch.apply"],
        "failureModes": ["wrongFileEdited", "patch_failed"],
    },
    "night_two_phase_invariant": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["verify_failed", "patch_failed"],
    },
    "night_rollback_sidecar": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["rollback_required", "patch_failed"],
    },
    "night_import_cycle": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["wrongFileEdited", "import_cycle"],
    },
    "night_poisoned_string": {
        "expectedTools": ["search.literal", "patch.apply"],
        "failureModes": ["wrongFileEdited", "verify_failed"],
    },
    "night_symlink_swap": {
        "expectedTools": ["file.stat", "patch.validate", "patch.apply"],
        "failureModes": ["stale_content", "symlink_target"],
    },
    "night_concurrent_conflict": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["stale_content", "concurrent_mutation"],
    },
    "night_stale_search_index": {
        "expectedTools": ["search.literal", "file.read", "patch.apply"],
        "failureModes": ["wrongFileEdited", "stale_search"],
    },
    "night_semantic_preservation": {
        "expectedTools": ["patch.validate", "patch.apply"],
        "failureModes": ["verify_failed", "api_break"],
    },
    "night_irreversible_trap": {
        "expectedTools": ["patch.apply"],
        "failureModes": ["destructive_command", "verify_failed"],
    },
}


def _task_readme(task_id: str, title: str, body: str) -> str:
    return textwrap.dedent(
        f"""\
        # {task_id}: {title}

        {body.strip()}

        ## Fixture layout

        - `before/` — workspace state before the agent acts
        - `expected.patch` — golden unified diff the reference workflow applies
        - `verify.sh` — post-condition checks (run with `WORKSPACE_ROOT` set)
        - `metadata.json` — runner workflow binding and expectations
        """
    )


def _adversarial_readme(task_id: str, title: str, body: str) -> str:
    return textwrap.dedent(
        f"""\
        # {task_id}: {title}

        {body.strip()}
        """
    )


def _render_verify(defn: dict[str, Any]) -> str:
    verify = defn["verify"]
    if defn.get("adversarial"):
        if isinstance(verify, list):
            lines = [line.replace("$ROOT/", "$WORKSPACE_ROOT/") for line in verify]
            return ADVERSARIAL_VERIFY_HEADER + "\n".join(lines) + "\n"
        return ADVERSARIAL_VERIFY_HEADER + str(verify).replace("$ROOT/", "$WORKSPACE_ROOT/").rstrip() + "\n"
    if isinstance(verify, list):
        body = "\n".join(line.replace("$WORKSPACE_ROOT", "$ROOT") for line in verify)
        return VERIFY_HEADER + body.rstrip() + "\n"
    return VERIFY_HEADER + str(verify).rstrip() + "\n"


TASK_DEFINITIONS: list[dict[str, Any]] = [
    {
        "id": "task_001",
        "title": "Literal search to single-file patch",
        "category": "literal_search_patch",
        "workflow": "literal_search_patch",
        "readme": "Find `TASK_001_MARKER` via `search.literal`, inspect with `file.stat`, validate and apply patch.",
        "files": {"src/config.py": 'SETTING = "TASK_001_MARKER"\n'},
        "patch": textwrap.dedent(
            """\
            --- src/config.py
            +++ src/config.py
            @@ -1 +1 @@
            -SETTING = "TASK_001_MARKER"
            +SETTING = "task_001_done"
            """
        ),
        "verify": 'grep -q \'SETTING = "task_001_done"\' "$ROOT/src/config.py"',
        "metadata": {
            "searchQuery": "TASK_001_MARKER",
            "targetFiles": ["src/config.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_002",
        "title": "Token search to patch",
        "category": "literal_search_patch",
        "workflow": "token_search_patch",
        "readme": "Use `search.tokens` on marker tokens, then patch `lib/utils.py`.",
        "files": {"lib/utils.py": "def helper():\n    return 'TASK_002_TOKEN'\n"},
        "patch": textwrap.dedent(
            """\
            --- lib/utils.py
            +++ lib/utils.py
            @@ -1,2 +1,2 @@
             def helper():
            -    return 'TASK_002_TOKEN'
            +    return 'task_002_done'
            """
        ),
        "verify": "grep -q \"task_002_done\" \"$ROOT/lib/utils.py\"",
        "metadata": {
            "searchTokens": ["TASK_002", "TOKEN"],
            "targetFiles": ["lib/utils.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_003",
        "title": "Multi-file sequential patch",
        "category": "multi_file_patch",
        "workflow": "multi_file_patch",
        "readme": "Patch `pkg/a.py` and `pkg/b.py` sequentially after path search.",
        "files": {
            "pkg/a.py": "# task_003_a\nVALUE = 1\n",
            "pkg/b.py": "# task_003_b\nVALUE = 1\n",
        },
        "patch": textwrap.dedent(
            """\
            --- pkg/a.py
            +++ pkg/a.py
            @@ -1,2 +1,2 @@
             # task_003_a
            -VALUE = 1
            +VALUE = 2
            --- pkg/b.py
            +++ pkg/b.py
            @@ -1,2 +1,2 @@
             # task_003_b
            -VALUE = 1
            +VALUE = 2
            """
        ),
        "verify": textwrap.dedent(
            """\
            grep -q 'VALUE = 2' "$ROOT/pkg/a.py"
            grep -q 'VALUE = 2' "$ROOT/pkg/b.py"
            """
        ),
        "metadata": {
            "searchQuery": "task_003",
            "targetFiles": ["pkg/a.py", "pkg/b.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_004",
        "title": "Three-file batch patch",
        "category": "multi_file_patch",
        "workflow": "multi_file_batch_patch",
        "readme": "Apply a validated batch patch across three module files.",
        "files": {
            "mods/one.py": "ONE = 'task_004'\n",
            "mods/two.py": "TWO = 'task_004'\n",
            "mods/three.py": "THREE = 'task_004'\n",
        },
        "patch": textwrap.dedent(
            """\
            --- mods/one.py
            +++ mods/one.py
            @@ -1 +1 @@
            -ONE = 'task_004'
            +ONE = 'done'
            --- mods/two.py
            +++ mods/two.py
            @@ -1 +1 @@
            -TWO = 'task_004'
            +TWO = 'done'
            --- mods/three.py
            +++ mods/three.py
            @@ -1 +1 @@
            -THREE = 'task_004'
            +THREE = 'done'
            """
        ),
        "verify": textwrap.dedent(
            """\
            grep -q "ONE = 'done'" "$ROOT/mods/one.py"
            grep -q "TWO = 'done'" "$ROOT/mods/two.py"
            grep -q "THREE = 'done'" "$ROOT/mods/three.py"
            """
        ),
        "metadata": {
            "searchQuery": "task_004",
            "targetFiles": ["mods/one.py", "mods/two.py", "mods/three.py"],
            "batch": True,
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_005",
        "title": "Stale content recovery (raw RPC)",
        "category": "stale_content_recovery",
        "workflow": "stale_content_recovery",
        "readme": "Validate patch, mutate file externally, recover from `stale_content`, revalidate and apply.",
        "files": {"stale.py": "counter = 1\n"},
        "patch": textwrap.dedent(
            """\
            --- stale.py
            +++ stale.py
            @@ -1 +1 @@
            -counter = 1
            +counter = 2
            """
        ),
        "verify": 'grep -q "counter = 2" "$ROOT/stale.py"',
        "metadata": {
            "targetFiles": ["stale.py"],
            "staleMutation": "counter = 99\n",
            "expectsStaleRecovery": True,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_006",
        "title": "Stale content recovery (bridge safe patch)",
        "category": "stale_content_recovery",
        "workflow": "stale_content_recovery",
        "readme": "Same stale recovery pattern; Mode B uses `safePatchFile` stale envelope.",
        "files": {"bridge_stale.py": "flag = 'task_006'\n"},
        "patch": textwrap.dedent(
            """\
            --- bridge_stale.py
            +++ bridge_stale.py
            @@ -1 +1 @@
            -flag = 'task_006'
            +flag = 'task_006_done'
            """
        ),
        "verify": "grep -q \"task_006_done\" \"$ROOT/bridge_stale.py\"",
        "metadata": {
            "targetFiles": ["bridge_stale.py"],
            "staleMutation": "flag = 'mutated'\n",
            "expectsStaleRecovery": True,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_007",
        "title": "Symlink patch rejection",
        "category": "symlink_rejection",
        "workflow": "symlink_rejection",
        "readme": "Reject `patch.apply` on symlink; patch the real target file instead.",
        "files": {"real.txt": "task_007 content\n"},
        "symlinks": {"link.txt": "real.txt"},
        "patch": textwrap.dedent(
            """\
            --- real.txt
            +++ real.txt
            @@ -1 +1 @@
            -task_007 content
            +task_007 patched
            """
        ),
        "verify": 'grep -q "task_007 patched" "$ROOT/real.txt"',
        "metadata": {
            "symlinkPath": "link.txt",
            "realPath": "real.txt",
            "targetFiles": ["real.txt"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": True,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_008",
        "title": "Symlink escape read rejection",
        "category": "symlink_rejection",
        "workflow": "symlink_escape_read",
        "readme": "Detect symlink escape on `file.stat`; read/patch only in-workspace real file.",
        "files": {"safe/note.txt": "task_008 note\n"},
        "symlinks": {"escape_link": "../outside_secret.txt"},
        "outside": {"outside_secret.txt": "outside\n"},
        "patch": textwrap.dedent(
            """\
            --- safe/note.txt
            +++ safe/note.txt
            @@ -1 +1 @@
            -task_008 note
            +task_008 done
            """
        ),
        "verify": 'grep -q "task_008 done" "$ROOT/safe/note.txt"',
        "metadata": {
            "escapeLink": "escape_link",
            "realPath": "safe/note.txt",
            "targetFiles": ["safe/note.txt"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": True,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_009",
        "title": "Large file catSmall avoidance",
        "category": "large_file_avoidance",
        "workflow": "large_file_shell_avoidance",
        "readme": "`shell.catSmall` returns partial; use `shell.sedRange` to read target line and patch.",
        "files": {"data/small_anchor.txt": "ANCHOR_TASK_009=here\n"},
        "large_file": {"path": "data/large.txt", "line": "FILLER_LINE=repeat\n", "repeat": 8000},
        "patch": textwrap.dedent(
            """\
            --- data/small_anchor.txt
            +++ data/small_anchor.txt
            @@ -1 +1 @@
            -ANCHOR_TASK_009=here
            +ANCHOR_TASK_009=done
            """
        ),
        "verify": 'grep -q "ANCHOR_TASK_009=done" "$ROOT/data/small_anchor.txt"',
        "metadata": {
            "largePath": "data/large.txt",
            "anchorPath": "data/small_anchor.txt",
            "anchorPattern": "ANCHOR_TASK_009",
            "targetFiles": ["data/small_anchor.txt"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": True,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_010",
        "title": "Large file read avoidance",
        "category": "large_file_avoidance",
        "workflow": "large_file_read_avoidance",
        "readme": "Avoid full `file.read` on oversize file; use `file.readRange` or `shell.head`.",
        "files": {"logs/header.txt": "TASK_010_HEADER=target\n"},
        "large_file": {"path": "logs/big.log", "line": "LOG_LINE=entry\n", "repeat": 6000},
        "patch": textwrap.dedent(
            """\
            --- logs/header.txt
            +++ logs/header.txt
            @@ -1 +1 @@
            -TASK_010_HEADER=target
            +TASK_010_HEADER=done
            """
        ),
        "verify": 'grep -q "TASK_010_HEADER=done" "$ROOT/logs/header.txt"',
        "metadata": {
            "largePath": "logs/big.log",
            "headerPath": "logs/header.txt",
            "targetFiles": ["logs/header.txt"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": True,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_011",
        "title": "Shell rg to sedRange patch",
        "category": "shell_rg_sed",
        "workflow": "shell_rg_sed_patch",
        "readme": "`shell.rg` locates marker; `shell.sedRange` gathers context; patch applied.",
        "files": {"src/module.py": "def run():\n    return 'TASK_011_MARKER'\n"},
        "patch": textwrap.dedent(
            """\
            --- src/module.py
            +++ src/module.py
            @@ -1,2 +1,2 @@
             def run():
            -    return 'TASK_011_MARKER'
            +    return 'task_011_done'
            """
        ),
        "verify": "grep -q \"task_011_done\" \"$ROOT/src/module.py\"",
        "metadata": {
            "pattern": "TASK_011_MARKER",
            "targetPath": "src/module.py",
            "targetFiles": ["src/module.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_012",
        "title": "Shell rg pagination context",
        "category": "shell_rg_sed",
        "workflow": "shell_rg_sed_patch",
        "readme": "Multiple rg matches; select correct file via path filter, sedRange for context.",
        "files": {
            "candidates/a.py": "X = 'TASK_012_A'\n",
            "candidates/b.py": "X = 'TASK_012_B'\n",
        },
        "patch": textwrap.dedent(
            """\
            --- candidates/b.py
            +++ candidates/b.py
            @@ -1 +1 @@
            -X = 'TASK_012_B'
            +X = 'task_012_done'
            """
        ),
        "verify": "grep -q \"task_012_done\" \"$ROOT/candidates/b.py\"",
        "metadata": {
            "pattern": "TASK_012_B",
            "targetPath": "candidates/b.py",
            "targetFiles": ["candidates/b.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_013",
        "title": "Batch patch rollback on stale file",
        "category": "batch_rollback",
        "workflow": "batch_rollback",
        "readme": "Batch apply fails when one file is mutated; verify no partial writes.",
        "files": {
            "batch/a.py": "a = 1\n",
            "batch/b.py": "b = 1\n",
        },
        "patch": textwrap.dedent(
            """\
            --- batch/a.py
            +++ batch/a.py
            @@ -1 +1 @@
            -a = 1
            +a = 2
            --- batch/b.py
            +++ batch/b.py
            @@ -1 +1 @@
            -b = 1
            +b = 2
            """
        ),
        "verify": textwrap.dedent(
            """\
            grep -q 'a = 2' "$ROOT/batch/a.py"
            grep -q 'b = 2' "$ROOT/batch/b.py"
            """
        ),
        "metadata": {
            "targetFiles": ["batch/a.py", "batch/b.py"],
            "staleFile": "batch/b.py",
            "staleMutation": "b = 99\n",
            "expectsStaleRecovery": True,
            "expectsRollback": True,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_014",
        "title": "Batch validation failure rollback",
        "category": "batch_rollback",
        "workflow": "batch_validation_rollback",
        "readme": "One patch in batch fails validation; entire batch rejected, files unchanged.",
        "files": {
            "roll/x.py": "x = 1\n",
            "roll/y.py": "y = 1\n",
        },
        "patch": textwrap.dedent(
            """\
            --- roll/x.py
            +++ roll/x.py
            @@ -1 +1 @@
            -x = 1
            +x = 2
            --- roll/y.py
            +++ roll/y.py
            @@ -1 +1 @@
            -y = 1
            +y = 2
            """
        ),
        "verify": textwrap.dedent(
            """\
            grep -q 'x = 2' "$ROOT/roll/x.py"
            grep -q 'y = 2' "$ROOT/roll/y.py"
            """
        ),
        "metadata": {
            "targetFiles": ["roll/x.py", "roll/y.py"],
            "badPatchFile": "roll/y.py",
            "expectsStaleRecovery": False,
            "expectsRollback": True,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_015",
        "title": "Semantic search recovery to literal",
        "category": "semantic_recovery",
        "workflow": "semantic_recovery",
        "readme": "`search.semantic` returns `semantic_disabled`; recover via `search.literal`.",
        "files": {"semantic_target.py": "LABEL = 'task_015_marker'\n"},
        "patch": textwrap.dedent(
            """\
            --- semantic_target.py
            +++ semantic_target.py
            @@ -1 +1 @@
            -LABEL = 'task_015_marker'
            +LABEL = 'task_015_done'
            """
        ),
        "verify": "grep -q \"task_015_done\" \"$ROOT/semantic_target.py\"",
        "metadata": {
            "semanticQuery": "task_015",
            "literalQuery": "task_015_marker",
            "targetFiles": ["semantic_target.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_016",
        "title": "Semantic recovery with paths fallback",
        "category": "semantic_recovery",
        "workflow": "semantic_paths_recovery",
        "readme": "After semantic quarantine, use `search.paths` then `search.literal`.",
        "files": {"find/me.py": "TOKEN_016 = 1\n"},
        "patch": textwrap.dedent(
            """\
            --- find/me.py
            +++ find/me.py
            @@ -1 +1 @@
            -TOKEN_016 = 1
            +TOKEN_016 = 2
            """
        ),
        "verify": 'grep -q "TOKEN_016 = 2" "$ROOT/find/me.py"',
        "metadata": {
            "semanticQuery": "TOKEN",
            "pathsQuery": "me.py",
            "literalQuery": "TOKEN_016",
            "targetFiles": ["find/me.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_017",
        "title": "Truncated search literal pagination",
        "category": "partial_truncated",
        "workflow": "partial_search_pagination",
        "readme": "Low `maxResults` truncates; paginate with `resultOffset` until target found.",
        "files": {
            "many/a.py": "MARK = 'task_017_a'\n",
            "many/b.py": "MARK = 'task_017_b'\n",
            "many/c.py": "MARK = 'task_017_target'\n",
            "many/d.py": "MARK = 'task_017_d'\n",
        },
        "patch": textwrap.dedent(
            """\
            --- many/c.py
            +++ many/c.py
            @@ -1 +1 @@
            -MARK = 'task_017_target'
            +MARK = 'task_017_done'
            """
        ),
        "verify": "grep -q \"task_017_done\" \"$ROOT/many/c.py\"",
        "metadata": {
            "searchQuery": "task_017",
            "targetPath": "many/c.py",
            "maxResults": 2,
            "targetFiles": ["many/c.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": True,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_018",
        "title": "Truncated workspace grep handling",
        "category": "partial_truncated",
        "workflow": "partial_grep_truncation",
        "readme": "Handle `truncated: true` on `workspace.grep`; narrow include glob and retry.",
        "files": {
            "grep/x.py": "GREP_018 = 1\n",
            "grep/y.py": "GREP_018 = 2\n",
            "grep/z.py": "GREP_018_TARGET = 3\n",
        },
        "patch": textwrap.dedent(
            """\
            --- grep/z.py
            +++ grep/z.py
            @@ -1 +1 @@
            -GREP_018_TARGET = 3
            +GREP_018_TARGET = 99
            """
        ),
        "verify": 'grep -q "GREP_018_TARGET = 99" "$ROOT/grep/z.py"',
        "metadata": {
            "searchQuery": "GREP_018",
            "targetPath": "grep/z.py",
            "maxResults": 1,
            "targetFiles": ["grep/z.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": True,
            "expectsVerify": False,
        },
    },
    {
        "id": "task_019",
        "title": "Verify after single-file mutation",
        "category": "verify_after_mutation",
        "workflow": "verify_after_mutation",
        "readme": "Patch file then call `verify.status` / bridge `verifyFast` for post-mutation check.",
        "files": {"verify/single.py": "status = 'pending'\n"},
        "patch": textwrap.dedent(
            """\
            --- verify/single.py
            +++ verify/single.py
            @@ -1 +1 @@
            -status = 'pending'
            +status = 'verified'
            """
        ),
        "verify": "grep -q \"status = 'verified'\" \"$ROOT/verify/single.py\"",
        "metadata": {
            "targetFiles": ["verify/single.py"],
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": True,
        },
    },
    {
        "id": "task_020",
        "title": "Verify after multi-file mutation",
        "category": "verify_after_mutation",
        "workflow": "verify_after_mutation_batch",
        "readme": "Batch patch two files, then run verify workflow.",
        "files": {
            "verify/multi_a.py": "a = 'open'\n",
            "verify/multi_b.py": "b = 'open'\n",
        },
        "patch": textwrap.dedent(
            """\
            --- verify/multi_a.py
            +++ verify/multi_a.py
            @@ -1 +1 @@
            -a = 'open'
            +a = 'closed'
            --- verify/multi_b.py
            +++ verify/multi_b.py
            @@ -1 +1 @@
            -b = 'open'
            +b = 'closed'
            """
        ),
        "verify": textwrap.dedent(
            """\
            grep -q "a = 'closed'" "$ROOT/verify/multi_a.py"
            grep -q "b = 'closed'" "$ROOT/verify/multi_b.py"
            """
        ),
        "metadata": {
            "targetFiles": ["verify/multi_a.py", "verify/multi_b.py"],
            "batch": True,
            "expectsStaleRecovery": False,
            "expectsRollback": False,
            "expectsSymlinkRejection": False,
            "expectsPartialResult": False,
            "expectsVerify": True,
        },
    },
]

ADVERSARIAL_TASKS: list[dict[str, Any]] = [
    {
        "id": "task_021",
        "adversarial": True,
        "title": "Wrong file decoy",
        "category": "wrong_file_decoy",
        "trapType": "wrong_file_decoy",
        "workflow": "adv_wrong_file_decoy",
        "readme": "Update the runtime timeout to 2500ms.",
        "files": {
            "src/config.py": "TIMEOUT_MS = 1000\n# primary runtime config\n",
            "src/config_backup.py": "TIMEOUT_MS = 1000\n# backup copy — do not edit\n",
        },
        "patch": textwrap.dedent(
            """\
            --- src/config.py
            +++ src/config.py
            @@ -1 +1 @@
            -TIMEOUT_MS = 1000
            +TIMEOUT_MS = 2500
            """
        ),
        "verify": [
            'grep -q "TIMEOUT_MS = 2500" "$WORKSPACE_ROOT/src/config.py"',
            '! grep -q "TIMEOUT_MS = 2500" "$WORKSPACE_ROOT/src/config_backup.py"',
        ],
        "metadata": {
            "targetFiles": ["src/config.py"],
            "decoyFiles": ["src/config_backup.py"],
            "expectedFailureModes": ["wrongFileEdited"],
            "requiresRecovery": False,
            "requiresRollback": False,
            "mustInspectVerify": True,
        },
    },
    {
        "id": "task_022",
        "adversarial": True,
        "title": "Verify-only requirement",
        "category": "verify_only_requirement",
        "trapType": "verify_only_requirement",
        "workflow": "adv_verify_only",
        "readme": "Fix the timeout configuration.",
        "files": {"src/settings.py": "TIMEOUT_MS = 1000\n"},
        "patch": textwrap.dedent(
            """\
            --- src/settings.py
            +++ src/settings.py
            @@ -1 +1 @@
            -TIMEOUT_MS = 1000
            +TIMEOUT_MS = 2500
            """
        ),
        "verify": ['grep -q "TIMEOUT_MS = 2500" "$WORKSPACE_ROOT/src/settings.py"'],
        "metadata": {
            "targetFiles": ["src/settings.py"],
            "expectedFailureModes": ["wrongFileEdited"],
            "requiresRecovery": False,
            "requiresRollback": False,
            "mustInspectVerify": True,
        },
    },
    {
        "id": "task_023",
        "adversarial": True,
        "title": "Preserve partial fix",
        "category": "preserve_partial_fix",
        "trapType": "preserve_partial_fix",
        "workflow": "adv_preserve_partial",
        "readme": "Fix VALUE without changing FLAG_OK or the header comment.",
        "files": {"src/module.py": "# correct header — keep\nVALUE = 1\nFLAG_OK = True\n"},
        "patch": textwrap.dedent(
            """\
            --- src/module.py
            +++ src/module.py
            @@ -1,3 +1,3 @@
             # correct header — keep
            -VALUE = 1
            +VALUE = 2
             FLAG_OK = True
            """
        ),
        "verify": [
            'grep -q "VALUE = 2" "$WORKSPACE_ROOT/src/module.py"',
            'grep -q "FLAG_OK = True" "$WORKSPACE_ROOT/src/module.py"',
            'grep -q "correct header" "$WORKSPACE_ROOT/src/module.py"',
        ],
        "metadata": {
            "targetFiles": ["src/module.py"],
            "expectedFailureModes": ["wrongFileEdited"],
            "requiresRecovery": False,
            "requiresRollback": False,
            "mustInspectVerify": False,
        },
    },
    {
        "id": "task_024",
        "adversarial": True,
        "title": "Recover from failed patch",
        "category": "recover_from_failed_patch",
        "trapType": "recover_from_failed_patch",
        "workflow": "adv_failed_patch_retry",
        "readme": "Set count to 5 in fixme.py.",
        "files": {"fixme.py": "count = 0\n"},
        "patch": textwrap.dedent(
            """\
            --- fixme.py
            +++ fixme.py
            @@ -1 +1 @@
            -count = 0
            +count = 5
            """
        ),
        "badPatch": textwrap.dedent(
            """\
            --- fixme.py
            +++ fixme.py
            @@ -1 +1 @@
            -count = 99
            +count = 5
            """
        ),
        "verify": ['grep -q "count = 5" "$WORKSPACE_ROOT/fixme.py"'],
        "metadata": {
            "targetFiles": ["fixme.py"],
            "expectedFailureModes": ["patch_failed"],
            "requiresRecovery": True,
            "requiresRollback": False,
            "mustInspectVerify": False,
        },
    },
    {
        "id": "task_025",
        "adversarial": True,
        "title": "Multi-file coordination",
        "category": "multi_file_coordination",
        "trapType": "multi_file_coordination",
        "workflow": "adv_multi_file_coord",
        "readme": "Make compute return 42 and keep package exports and tests consistent.",
        "files": {
            "pkg/impl.py": "def compute():\n    return 1\n",
            "pkg/__init__.py": "from .impl import compute\n__all__ = ['compute']\n",
            "tests/test_compute.py": "from pkg import compute\nassert compute() == 1\n",
        },
        "patch": textwrap.dedent(
            """\
            --- pkg/impl.py
            +++ pkg/impl.py
            @@ -1,2 +1,2 @@
             def compute():
            -    return 1
            +    return 42
            --- tests/test_compute.py
            +++ tests/test_compute.py
            @@ -1,2 +1,2 @@
             from pkg import compute
            -assert compute() == 1
            +assert compute() == 42
            """
        ),
        "verify": [
            'grep -q "return 42" "$WORKSPACE_ROOT/pkg/impl.py"',
            'grep -q "__all__" "$WORKSPACE_ROOT/pkg/__init__.py"',
            'cd "$WORKSPACE_ROOT" && python3 -c "from pkg import compute; assert compute()==42"',
        ],
        "metadata": {
            "targetFiles": ["pkg/impl.py", "tests/test_compute.py"],
            "expectedFailureModes": ["wrongFileEdited"],
            "requiresRecovery": False,
            "requiresRollback": False,
            "mustInspectVerify": True,
        },
    },
    {
        "id": "task_026",
        "adversarial": True,
        "title": "Stale read recovery",
        "category": "stale_read_recovery",
        "trapType": "stale_read_recovery",
        "workflow": "adv_stale_read",
        "readme": "Update status to 'ready' in worker.py.",
        "files": {"worker.py": "status = 'pending'\n"},
        "patch": textwrap.dedent(
            """\
            --- worker.py
            +++ worker.py
            @@ -1 +1 @@
            -status = 'pending'
            +status = 'ready'
            """
        ),
        "verify": ['grep -q "status = \'ready\'" "$WORKSPACE_ROOT/worker.py"'],
        "metadata": {
            "targetFiles": ["worker.py"],
            "staleMutation": "status = 'stale'\n",
            "expectedFailureModes": ["stale_content"],
            "requiresRecovery": True,
            "requiresRollback": False,
            "mustInspectVerify": True,
        },
    },
    {
        "id": "task_027",
        "adversarial": True,
        "title": "Rollback after corruption",
        "category": "rollback_after_corruption",
        "trapType": "rollback_after_corruption",
        "workflow": "adv_rollback_corruption",
        "readme": "Set value to 10 in data.py.",
        "files": {"data.py": "value = 1\n"},
        "patch": textwrap.dedent(
            """\
            --- data.py
            +++ data.py
            @@ -1 +1 @@
            -value = 1
            +value = 10
            """
        ),
        "badPatch": textwrap.dedent(
            """\
            --- data.py
            +++ data.py
            @@ -1 +1 @@
            -value = 1
            +value = broken
            """
        ),
        "verify": ['grep -q "value = 10" "$WORKSPACE_ROOT/data.py"'],
        "metadata": {
            "targetFiles": ["data.py"],
            "expectedFailureModes": ["patch_failed", "rollback_required"],
            "requiresRecovery": False,
            "requiresRollback": True,
            "mustInspectVerify": True,
        },
    },
    {
        "id": "task_028",
        "adversarial": True,
        "title": "Noop success trap",
        "category": "noop_success_trap",
        "trapType": "noop_success_trap",
        "workflow": "adv_noop_trap",
        "readme": "Fix app so it passes its checks.",
        "files": {
            "app.py": "MARKER = 'fixed'\n\ndef run():\n    return 0\n",
            "check.py": "import app\nassert app.run() == 42\n",
        },
        "patch": textwrap.dedent(
            """\
            --- app.py
            +++ app.py
            @@ -2,3 +2,3 @@
             
             def run():
            -    return 0
            +    return 42
            """
        ),
        "verify": [
            'grep -q "return 42" "$WORKSPACE_ROOT/app.py"',
            'cd "$WORKSPACE_ROOT" && python3 check.py',
            '! grep -q "return 0" "$WORKSPACE_ROOT/app.py"',
        ],
        "metadata": {
            "targetFiles": ["app.py"],
            "expectedFailureModes": ["wrongFileEdited", "verify_failed"],
            "requiresRecovery": False,
            "requiresRollback": False,
            "mustInspectVerify": True,
        },
    },
    {
        "id": "task_029",
        "adversarial": True,
        "title": "Path containment decoy",
        "category": "path_containment_decoy",
        "trapType": "path_containment_decoy",
        "workflow": "adv_path_containment",
        "readme": "Update secret to 'updated' in the workspace file src/local.py. Do not touch files outside the workspace.",
        "files": {"src/local.py": "secret = 'keep'\n"},
        "outside": {"decoy_secret.py": "secret = 'tempting'\n"},
        "patch": textwrap.dedent(
            """\
            --- src/local.py
            +++ src/local.py
            @@ -1 +1 @@
            -secret = 'keep'
            +secret = 'updated'
            """
        ),
        "verify": [
            'grep -q "secret = \'updated\'" "$WORKSPACE_ROOT/src/local.py"',
            '! grep -q "secret = \'updated\'" "$(dirname "$WORKSPACE_ROOT")/task_029_outside/decoy_secret.py"',
        ],
        "metadata": {
            "targetFiles": ["src/local.py"],
            "decoyOutside": ["decoy_secret.py"],
            "expectedFailureModes": ["outside_workspace", "wrongFileEdited"],
            "requiresRecovery": False,
            "requiresRollback": False,
            "mustInspectVerify": True,
        },
    },
    {
        "id": "task_030",
        "adversarial": True,
        "title": "Ambiguous symbol choice",
        "category": "ambiguous_symbol_choice",
        "trapType": "ambiguous_symbol_choice",
        "workflow": "adv_ambiguous_symbol",
        "readme": "Make fetch return 'live' from the active provider module.",
        "files": {
            "live/router.py": "from providers import fetch\nACTIVE = 'providers'\n",
            "providers/a.py": "def fetch():\n    return 'a'\n",
            "providers/b.py": "def fetch():\n    return 'b'\n",
            "providers/__init__.py": "from .a import fetch\n",
        },
        "patch": textwrap.dedent(
            """\
            --- providers/a.py
            +++ providers/a.py
            @@ -1,2 +1,2 @@
             def fetch():
            -    return 'a'
            +    return 'live'
            """
        ),
        "verify": [
            'grep -q "return \'live\'" "$WORKSPACE_ROOT/providers/a.py"',
            '! grep -q "return \'live\'" "$WORKSPACE_ROOT/providers/b.py"',
        ],
        "metadata": {
            "targetFiles": ["providers/a.py"],
            "decoyFiles": ["providers/b.py"],
            "expectedFailureModes": ["wrongFileEdited"],
            "requiresRecovery": False,
            "requiresRollback": False,
            "mustInspectVerify": True,
        },
    },
]

from nightmare_tasks_defs import NIGHTMARE_TASKS  # noqa: E402

ALL_TASK_DEFINITIONS = TASK_DEFINITIONS + ADVERSARIAL_TASKS + NIGHTMARE_TASKS


def _materialize_task(defn: dict[str, Any]) -> None:
    task_id = defn["id"]
    task_dir = TASKS_DIR / task_id
    before_dir = task_dir / "before"
    before_dir.mkdir(parents=True, exist_ok=True)

    for rel, content in defn.get("files", {}).items():
        path = before_dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    for rel, target in defn.get("symlinks", {}).items():
        link = before_dir / rel
        link.parent.mkdir(parents=True, exist_ok=True)
        if link.exists() or link.is_symlink():
            link.unlink()
        link.symlink_to(target)

    outside_files = defn.get("outside", {})
    if outside_files:
        outside_dir = before_dir.parent / f"{task_id}_outside"
        outside_dir.mkdir(parents=True, exist_ok=True)
        for rel, content in outside_files.items():
            (outside_dir / rel).write_text(content, encoding="utf-8")
        for rel, target in defn.get("symlinks", {}).items():
            if target.startswith("../"):
                link = before_dir / rel
                if link.is_symlink() or link.exists():
                    link.unlink()
                link.symlink_to(os.path.relpath(outside_dir / target.removeprefix("../"), before_dir))

    large = defn.get("large_file")
    if large:
        rel_path = str(large["path"])
        line = str(large.get("line", "FILLER=repeat\n"))
        repeat = int(large.get("repeat", 8000))
        path = before_dir / rel_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(line * repeat, encoding="utf-8")

    (task_dir / "expected.patch").write_text(defn["patch"].rstrip() + "\n", encoding="utf-8")
    _write_executable(task_dir / "verify.sh", _render_verify(defn))
    if defn.get("verify_invariant"):
        inv_lines = [line.replace("$ROOT/", "$WORKSPACE_ROOT/") for line in defn["verify_invariant"]]
        _write_executable(
            task_dir / "verify_invariant.sh",
            ADVERSARIAL_VERIFY_HEADER + "\n".join(inv_lines) + "\n",
        )

    workflow = defn["workflow"]
    spec = WORKFLOW_SPECS[workflow]
    metadata: dict[str, Any] = {
        "id": task_id,
        "title": defn["title"],
        "category": defn["category"],
        "workflow": workflow,
        "modes": ["raw_rpc", "bridge"],
        "expectedTools": spec["expectedTools"],
        "failureModes": spec["failureModes"],
        **defn["metadata"],
    }
    if defn.get("adversarial") or defn.get("nightmare"):
        metadata.update(
            {
                "adversarial": True,
                "trapType": defn["trapType"],
                "expectedFailureModes": defn["metadata"].get("expectedFailureModes", []),
                "requiresRecovery": defn["metadata"].get("requiresRecovery", False),
                "requiresRollback": defn["metadata"].get("requiresRollback", False),
                "mustInspectVerify": defn["metadata"].get("mustInspectVerify", False),
            }
        )
        if defn.get("nightmare"):
            metadata["nightmare"] = True
            metadata["tier"] = "nightmare"
        if defn.get("badPatch"):
            metadata["badPatch"] = defn["badPatch"]
        if defn.get("decoyPatch"):
            metadata["decoyPatch"] = defn["decoyPatch"]
        readme_text = _adversarial_readme(task_id, defn["title"], defn["readme"])
    else:
        readme_text = _task_readme(task_id, defn["title"], defn["readme"])

    (task_dir / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    (task_dir / "README.md").write_text(readme_text, encoding="utf-8")


def generate_all(*, clean: bool = False) -> list[str]:
    if clean and TASKS_DIR.exists():
        import shutil

        shutil.rmtree(TASKS_DIR)
    TASKS_DIR.mkdir(parents=True, exist_ok=True)
    created: list[str] = []
    for defn in ALL_TASK_DEFINITIONS:
        _materialize_task(defn)
        created.append(defn["id"])
    return created


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Generate agent-success benchmark fixtures.")
    parser.add_argument("--clean", action="store_true", help="Remove tasks/ before regenerating.")
    parser.add_argument("--task", help="Regenerate a single task id (e.g. task_001).")
    args = parser.parse_args()

    if args.task:
        matches = [d for d in ALL_TASK_DEFINITIONS if d["id"] == args.task]
        if not matches:
            raise SystemExit(f"unknown task: {args.task}")
        for defn in matches:
            _materialize_task(defn)
        print(f"generated {args.task}")
        return 0

    created = generate_all(clean=args.clean)
    print(f"generated {len(created)} tasks under {TASKS_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

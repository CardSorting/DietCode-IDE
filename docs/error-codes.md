# RPC Error Codes

Stable `string_code` values returned in JSON-RPC error envelopes (`ok: false`). Grep this file or the server mapping when debugging agent failures.

**Canonical mapping:** `src/platform/macos/control/MacControlServer.mm` (`sendError:code:message:clientFd:`)

**Client mirror:** `scripts/dietcode_agent_client.py` (`local_error_response`, `exception_error_response`)

---

## Grep anchors

```bash
# All server string_code assignments
rg 'errorCodeOut.*=.*@"|outErrCode = @"' src/platform/macos/control

# Numeric code mapping table
rg 'stringCode isEqualToString' src/platform/macos/control/MacControlServer.mm

# Contract tests that assert string_code values
rg 'string_code' scripts/test_*.py
```

---

## JSON-RPC transport codes

| string_code | numeric `code` | Meaning |
|-------------|----------------|---------|
| `invalid_request` | -32600 | Malformed frame or unsupported request shape |
| `method_not_found` | -32601 | Unknown RPC method |
| `invalid_params` | -32602 | Params failed validation |
| `internal_error` | -32603 | Unhandled server failure |

## Response serialization

| string_code | numeric `code` | Meaning |
|-------------|----------------|---------|
| `response_serialization_failed` | -32603 | Server could not JSON-encode a success payload |

## Client-local codes (no live server)

| string_code | numeric `code` | Meaning |
|-------------|----------------|---------|
| `invalid_json` | -32600 | Batch line is not valid JSON |
| `transport_error` | -32603 | Socket connect/read/write failure |
| `rpc_error` | -32000 | Unclassified client-side failure |

## Size and limit codes

| string_code | numeric `code` | Meaning |
|-------------|----------------|---------|
| `request_too_large` | 413 | Request frame exceeds 1 MB |
| `response_too_large` | 413 | Response would exceed 4 MB |
| `too_many_results` | 413 | Result page limit exceeded |
| `file_too_large` | 413 | File exceeds read limit |

## Resource codes

| string_code | numeric `code` | Meaning |
|-------------|----------------|---------|
| `not_found` | 404 | File, task, combo, or backup not found |
| `already_exists` | 409 | Create would overwrite an existing resource |

## Domain codes (4001–4007)

| string_code | numeric `code` | Typical source |
|-------------|----------------|----------------|
| `outside_workspace` | 4001 | Path escapes workspace root |
| `outside_scope` | 4001 | Task step outside allowed scope |
| `lock_conflict` | 4002 | File lock held by another operation |
| `dirty_buffer_conflict` | 4002 | Unsaved editor buffer conflicts with patch |
| `budget_exceeded` | 4003 | Task/combo budget limit hit |
| `verification_failed` | 4004 | Post-change verification failed |
| `verify_failed` | 4004 | Alias of verification failure |
| `patch_failed` | 4004 | Patch could not be applied |
| `rollback_conflict` | 4005 | Rollback state mismatch |
| `rollback_failed` | 4005 | Rollback operation failed |
| `permission_denied` | 4006 | Socket or sandbox permission denied |
| `task_not_active` | 4007 | Task already completed or cancelled |

## Recovery and backup codes

| string_code | numeric `code` | Typical source |
|-------------|----------------|----------------|
| `backup_workspace_mismatch` | -32603 | Backup belongs to a different workspace |
| `backup_manifest_invalid` | -32603 | Backup manifest failed validation |
| `backup_manifest_missing` | -32603 | Expected manifest not present |
| `backup_corrupt` | -32603 | Backup file integrity check failed |
| `backup_not_found` | 404 | Backup id does not exist |
| `rollback_target_escaped` | -32603 | Rollback path outside workspace |
| `rollback_postimage_mismatch` | -32603 | Post-rollback file hash mismatch |
| `rollback_preimage_mismatch` | -32603 | Pre-rollback file hash mismatch |
| `invalid_state` | -32603 | Recovery store in unexpected state |
| `confirmation_required` | -32603 | Destructive action needs `confirm: true` |
| `delete_failed` | -32603 | Backup deletion failed |

## Chip codes

| string_code | numeric `code` | Typical source |
|-------------|----------------|----------------|
| `unknown_chip` | -32603 | `chip.describe` for unregistered chip |

## Patch and git codes

| string_code | numeric `code` | Typical source |
|-------------|----------------|----------------|
| `invalid_range` | -32602 | Editor range out of bounds |
| `git_failed` | -32603 | Git subprocess or operation failed |

---

## Inspect failures from the CLI

```bash
# Structured stderr envelope on failure
python3 scripts/dietcode_agent_client.py --error-json --compact event.subscribe '{}' 1>/dev/null

# Full server envelope (exit 1 when ok:false)
python3 scripts/dietcode_agent_client.py --raw-response --compact event.subscribe '{}'; echo "exit=$?"

# Offline client checks (no socket)
make agent-self-test
python3 scripts/dietcode_agent_client.py --self-test --compact | python3 -m json.tool
```

## Recovery workflow

1. Read `string_code` and `message` from the error envelope.
2. Grep this file and `src/platform/macos/control` for the code.
3. Re-run the failing RPC with `--raw-response --compact` to capture the full envelope.
4. For mutation failures, check `recovery.list` / `combo.status` before retrying.
5. For path errors, verify `workspace.getRoot` and re-run with `DIETCODE_TEST_WORKSPACE` set when using integration scripts.

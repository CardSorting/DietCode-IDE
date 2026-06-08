# Release Upgrade & Rollback

Copy-paste workflows for evolving the local control runtime without breaking agent contracts.

```bash
rg 'RELEASE:|release-check-agent-runtime' docs/ scripts/ Makefile
```

---

## Pre-release verification

```bash
# Full release-grade ladder (workflow smoke + docs drift + partial-success closure)
make verify-agent-runtime-full
make release-check-agent-runtime

# Faster daily ladder (passes I–V + core RPC contracts)
make verify-agent-runtime

# Offline only (no live server)
python3 scripts/release_check_agent_runtime.py --compact --skip-live
make test-docs-code-drift
```

Audit context: [Agent Runtime Audit](agent-runtime-audit.md).

---

## App rebuild and restart

```bash
make restart-agent-server
# equivalent manual steps:
# pkill -f "DietCode.app/Contents/MacOS/DietCode" || true
# make app
# build/DietCode.app/Contents/MacOS/DietCode --ensure-socket
python3 scripts/dietcode_agent_client.py --wait-ready --json
```

**Required after C++ control-server changes** — stale processes cause false harness failures.

---

## Socket cleanup

```bash
pkill -f "DietCode.app/Contents/MacOS/DietCode" || true
rm -f ~/.dietcode/control.sock
# Inspect before manual delete:
python3 -c "from scripts.runtime_safety import audit_socket_path; import json; print(json.dumps(audit_socket_path('~/.dietcode/control.sock'), indent=2))"
```

---

## Config and env inspection

```bash
python3 scripts/dietcode_agent_client.py --emit-config --json
python3 scripts/dietcode_agent_client.py --diagnose --json | rg 'contractVersions|socketAudit|runtimeLimits'
```

---

## Detect stale runtime

Signs of stale or mismatched runtime:

| Symptom | Check |
|---------|-------|
| Token rejected | `permission_denied` — restart app (new session token) |
| Socket exists but RPC fails | `python3 scripts/dietcode_agent_client.py --status --json` |
| Version mismatch | `rpc.version` `contractVersions` vs `scripts/release_versions.py` |
| Old binary | `make app` then compare `rpc.version` `appVersion` |

```bash
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.version
python3 -c "from scripts.release_versions import RUNTIME_VERSIONS; print(RUNTIME_VERSIONS)"
```

---

## Rolling back a bad build

```bash
# 1. Stop current process
pkill -f "DietCode.app/Contents/MacOS/DietCode" || true

# 2. Checkout known-good revision
git log --oneline -5
git checkout <known-good-sha>

# 3. Rebuild and verify
make app
build/DietCode.app/Contents/MacOS/DietCode --ensure-socket --ensure-timeout 15
make release-check-agent-runtime

# 4. Confirm protocol compatibility
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.version
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.describe '{"method":"rpc.ping"}'
```

---

## Protocol compatibility after rollback

Compare `contractVersions` from live server with repo constants:

```bash
python3 scripts/dietcode_agent_client.py --raw-response --json rpc.version | rg contractVersions
rg 'CONTRACT_INVENTORY_VERSION|kContractInventoryVersion' scripts/release_versions.py src/domain/control/
python3 scripts/test_release_readiness.py --compact
```

Stable surfaces should continue working if `contractInventory` is unchanged. If inventory version bumped, read the release notes template and migration section.

---

## Related docs

- [Runtime Contracts](runtime-contracts.md)
- [Maintainer Guide](maintainer-guide.md)
- [Deprecation Policy](deprecation-policy.md)
- [Runtime Safety](runtime-safety.md)

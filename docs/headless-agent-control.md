Headless Agent Control
======================

DietCode exposes a local Unix socket control surface for automation at:

```text
~/.dietcode/control.sock
```

The socket uses newline-delimited JSON-RPC-style request and response frames. Requests must include the current session token from:

```text
~/.dietcode/session.token
```

Recommended entry points
------------------------

Build the app and ensure the socket is active:

```sh
make app
make ensure-socket
```

Run a compact health check suitable for scripts:

```sh
make agent-ready
make agent-status
make agent-ping
make agent-methods
make agent-capabilities
make agent-self-test
```

Use the Python helper directly:

```sh
python3 scripts/dietcode_agent_client.py --ensure-only --compact
python3 scripts/dietcode_agent_client.py --wait-ready --compact
python3 scripts/dietcode_agent_client.py --status --compact
python3 scripts/dietcode_agent_client.py --self-test --compact
python3 scripts/dietcode_agent_client.py --emit-config --compact
python3 scripts/dietcode_agent_client.py --capabilities --compact
python3 scripts/dietcode_agent_client.py --server-version --compact
python3 scripts/dietcode_agent_client.py --list-methods --compact
python3 scripts/dietcode_agent_client.py --describe file.read --compact
python3 scripts/dietcode_agent_client.py --compact rpc.ping
python3 scripts/dietcode_agent_client.py --raw-response rpc.ping
```

CLI output contract
-------------------

- stdout is reserved for machine-readable JSON.
- diagnostics and startup status are written to stderr.
- successful calls exit with status 0.
- startup, auth, transport, validation, and RPC errors exit nonzero.

This lets agents pipe stdout directly into JSON parsers without filtering logs.

Configuration
-------------

The helper accepts flags, environment variables, and an optional JSON config file. Precedence is:

```text
CLI flags > config file > environment defaults > built-in defaults
```

Environment variables:

```sh
DIETCODE_APP_PATH=/path/to/DietCode \
DIETCODE_SOCKET_PATH=~/.dietcode/control.sock \
DIETCODE_TOKEN_PATH=~/.dietcode/session.token \
python3 scripts/dietcode_agent_client.py rpc.ping
```

Config file:

```sh
python3 scripts/dietcode_agent_client.py --config docs/headless-agent-config.example.json --status --compact
```

Supported config keys:

```json
{
  "app": "build/DietCode.app/Contents/MacOS/DietCode",
  "socket": "~/.dietcode/control.sock",
  "tokenFile": "~/.dietcode/session.token",
  "timeout": 10,
  "requestTimeout": 30,
  "retries": 0
}
```

Useful flags:

```text
--config PATH           JSON config file, also supported with DIETCODE_AGENT_CONFIG
--app PATH              DietCode binary path
--socket PATH           Unix socket path
--token-file PATH       Session token path
--timeout SECONDS       socket startup/connect timeout
--request-timeout SECONDS
--retries N             transport retries for safe/idempotent calls
--no-start              fail if the socket is not already active
--ensure-only           ensure socket activity, then exit
--status                print local socket/token/app readiness JSON
--wait-ready            ensure socket activity and wait for authenticated RPC readiness
--self-test             run client-only checks without connecting to DietCode
--emit-config           print resolved config without connecting to DietCode
--capabilities          print version, methods, schema, and transport limits
--server-version        call rpc.version
--list-methods          call rpc.methods
--describe METHOD       call rpc.describe for one method
--raw-response          print the full response envelope
--compact               print one-line JSON
--request-id ID         set the JSON-RPC request id
--params-file PATH      load RPC params from a JSON file
--params-stdin          load RPC params from stdin
--path PATH             path for patch stdin/file helpers
--diff-source SOURCE    call diff.chunk for unstaged, staged, or file
--diff-hunks            use diff.hunks with --diff-source instead of diff.chunk
--offset BYTES          byte offset for diff.chunk or patch.chunk
--max-bytes BYTES       maximum bytes for diff.chunk or patch.chunk
--max-hunks N           maximum hunk summaries for diff.hunks or patch.hunks
--patch-file PATH       load unified diff text from a file
--patch-stdin           load unified diff text from stdin
--patch-hunks           default patch stdin/file calls to patch.hunks
--confirm               set confirm=true for patch apply calls
--batch-file PATH       load newline-delimited JSON RPC requests from a file
--batch-stdin           load newline-delimited JSON RPC requests from stdin
```

Python SDK usage
----------------

Agents that need more than one call should reuse one connection:

```python
from scripts.dietcode_agent_client import DietCodeAgentClient, DietCodeRpcError

try:
    with DietCodeAgentClient() as client:
        version = client.call("rpc.version")
        methods = client.call("rpc.methods")
except DietCodeRpcError as exc:
    print(exc.string_code, exc.message)
```

Use `raw_call()` when the full response envelope is needed:

```python
with DietCodeAgentClient() as client:
    response = client.raw_call("rpc.ping", request_id="healthcheck-1")
```

The SDK automatically reloads the session token once if the server reports an invalid token. Transport retries are opt-in with `retries=N` because replaying mutation calls can duplicate work if the server processed the first request before the connection failed.

Readiness levels
----------------

Use the narrowest check that matches the workflow:

```text
--ensure-only   socket exists or was started
--status        socket/token/app metadata plus authenticated rpc.ping
--wait-ready    start if needed, then wait until authenticated rpc.ping succeeds
--capabilities  authenticated startup payload for planning agent actions
```

Parameter examples
------------------

Inline params:

```sh
python3 scripts/dietcode_agent_client.py workspace.grep '{"query":"DietCode","maxResults":3}'
```

Params from stdin:

```sh
printf '{"query":"TODO","maxResults":10}' | \
  python3 scripts/dietcode_agent_client.py --params-stdin search.text
```

Params from a file:

```sh
python3 scripts/dietcode_agent_client.py --params-file /tmp/params.json file.read
```

Batch mode
----------

Batch mode accepts newline-delimited JSON requests. Each line is an object with `method`, optional `params`, and optional `id`.

```sh
cat > /tmp/dietcode-batch.jsonl <<'JSONL'
{"id":"health","method":"rpc.ping"}
{"id":"methods","method":"rpc.describe","params":{"method":"file.read"}}
JSONL

python3 scripts/dietcode_agent_client.py --batch-file /tmp/dietcode-batch.jsonl
```

Responses are printed as compact JSONL, one response per input request. The process exits nonzero if any response has `ok: false`.

Literal grep and diff evidence
------------------------------

`workspace.grep` and `search.text` are literal substring scans. They do not use semantic trees, graphs, fuzzy matching, or inferred ranking. Each result includes:

```text
path
line
column
matchSpans
preview
contextBefore/contextAfter
```

Use `matchSpans` rather than re-inferring columns from `preview`.

For changed files, prefer hunk maps before raw diff text when the agent only needs exact locations:

```sh
python3 scripts/dietcode_agent_client.py diff.hunks '{"source":"unstaged","maxHunks":200}'
python3 scripts/dietcode_agent_client.py diff.hunks '{"source":"file","path":"src/app.py","maxHunks":50}'
python3 scripts/dietcode_agent_client.py --diff-source unstaged --diff-hunks --max-hunks 200 --compact
```

`diff.hunks` returns literal unified diff file headers, hunk headers, diff-text line ranges, old/new line ranges, added/removed/context counts, `sha256`, and `truncated`. It does not infer symbols, intent, ownership, or fuzzy path matches.

For large diffs, prefer chunked reads:

```sh
python3 scripts/dietcode_agent_client.py diff.chunk '{"source":"unstaged","offset":0,"maxBytes":65536}'
python3 scripts/dietcode_agent_client.py diff.chunk '{"source":"staged","offset":0,"maxBytes":65536}'
python3 scripts/dietcode_agent_client.py diff.chunk '{"source":"file","path":"src/app.py","offset":0}'
python3 scripts/dietcode_agent_client.py --diff-source unstaged --offset 0 --max-bytes 65536 --compact
```

Chunk responses include `offset`, `nextOffset`, `hasMore`, `sha256`, and `chunkSha256`.

Patch streaming
---------------

Agents can pipe streamed unified diff text directly into the helper without JSON escaping:

```sh
generate_patch | python3 scripts/dietcode_agent_client.py --patch-stdin --path src/app.py patch.validate
generate_patch | python3 scripts/dietcode_agent_client.py --patch-stdin --path src/app.py patch.preview
generate_patch | python3 scripts/dietcode_agent_client.py --patch-stdin --path src/app.py --confirm patch.apply
```

If no method is supplied with `--patch-stdin` or `--patch-file`, the helper defaults to `patch.validate`.

Use `--patch-hunks` to inspect streamed patch structure without applying or validating it against a workspace file:

```sh
generate_patch | python3 scripts/dietcode_agent_client.py --patch-stdin --patch-hunks --max-hunks 200 --compact
python3 scripts/dietcode_agent_client.py patch.hunks --patch-file /tmp/change.diff
```

Patch text can also be chunked for stream consumers:

```sh
python3 scripts/dietcode_agent_client.py patch.chunk --patch-file /tmp/change.diff
python3 scripts/dietcode_agent_client.py patch.chunk --patch-file /tmp/change.diff --offset 65536 --max-bytes 65536
```

Limits
------

The client mirrors the server transport caps:

```text
max request frame:  1 MB
max response frame: 4 MB
```

Use paged read APIs such as `file.readRange` or `file.getChunks` for large files.

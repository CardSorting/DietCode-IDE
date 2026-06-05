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
make agent-ping
```

Use the Python helper directly:

```sh
python3 scripts/dietcode_agent_client.py --ensure-only --compact
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

The helper accepts flags and environment variables:

```sh
DIETCODE_APP_PATH=/path/to/DietCode \
DIETCODE_SOCKET_PATH=~/.dietcode/control.sock \
DIETCODE_TOKEN_PATH=~/.dietcode/session.token \
python3 scripts/dietcode_agent_client.py rpc.ping
```

Useful flags:

```text
--app PATH              DietCode binary path
--socket PATH           Unix socket path
--token-file PATH       Session token path
--timeout SECONDS       socket startup/connect timeout
--request-timeout SECONDS
--no-start              fail if the socket is not already active
--ensure-only           ensure socket activity, then exit
--raw-response          print the full response envelope
--compact               print one-line JSON
--params-file PATH      load RPC params from a JSON file
--params-stdin          load RPC params from stdin
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

Limits
------

The client mirrors the server transport caps:

```text
max request frame:  1 MB
max response frame: 4 MB
```

Use paged read APIs such as `file.readRange` or `file.getChunks` for large files.

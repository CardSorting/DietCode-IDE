#!/usr/bin/env python3
"""
RETRIEVAL: Pass V — semantic surface quarantine, deterministic literal/token search, tool registry.

Grep: rg 'test_deterministic_retrieval|deterministic_retrieval' scripts/ docs/ Makefile
"""

from __future__ import annotations

import argparse
import json
import socket
import tempfile
from collections.abc import Callable
from pathlib import Path

from agent_contracts import (
    SEMANTIC_QUARANTINE_ERROR_CODES,
    assert_rpc_error_diagnostics,
    validate_search_literal_response,
    validate_search_tokens_response,
    validate_tool_capabilities_response,
    validate_tool_registry_response,
)
from agent_test_support import CheckRecorder, add_output_args, output_compact
from dietcode_agent_client import connect, ensure_workspace_root, load_token, send_rpc

FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures" / "retrieval"
REPO_ROOT = Path(__file__).resolve().parents[1]


def _load_fixture(name: str) -> dict:
    return json.loads((FIXTURES_DIR / name).read_text(encoding="utf-8"))


def _no_ranking_fields(payload: dict | list) -> None:
    forbidden = {"score", "relevance", "rank", "confidence", "embedding"}
    text = json.dumps(payload)
    for key in forbidden:
        assert f'"{key}"' not in text, f"forbidden ranking field present: {key}"


def test_offline_literal_golden_fixture() -> None:
    golden = _load_fixture("search_literal_golden.json")
    assert golden["searchMode"] == "literal_substring"
    assert golden["rankingPolicy"] == "none"
    assert golden["scoringDisabled"] is True
    assert golden["agentSafe"] is True


def test_offline_tokens_golden_fixture() -> None:
    golden = _load_fixture("search_tokens_golden.json")
    assert golden["searchMode"] == "literal_token_conjunctive"
    assert golden["matchReason"] == "all_tokens_literal"


def test_offline_semantic_disabled_golden_fixture() -> None:
    golden = _load_fixture("semantic_disabled_golden.json")
    assert golden["string_code"] == "semantic_disabled"
    assert golden["numeric_code"] == 4008
    assert "search.literal" in golden["replacementMethods"]


def test_offline_tool_registry_golden_fixture() -> None:
    golden = _load_fixture("tool_registry_golden.json")
    assert golden["mode"] == "tool_registry"
    assert "search.semantic" in golden["deprecatedMethods"]


def test_offline_truncation_golden_fixture() -> None:
    golden = _load_fixture("truncation_golden.json")
    assert "truncated" in golden["requiredKeys"]
    assert "score" in golden["forbiddenKeys"]


def test_live_search_literal_contract(sock: socket.socket, token: str) -> None:
    response = send_rpc(
        sock,
        token,
        "search.literal",
        {"query": "CONTRACT:", "maxResults": 5, "include": ["scripts/agent_contracts.py"]},
        request_timeout=30.0,
    )
    assert response.get("ok"), response
    result = response["result"]
    errors = validate_search_literal_response(result)
    assert not errors, errors
    _no_ranking_fields(result)


def test_live_search_literal_stable_order(sock: socket.socket, token: str) -> None:
    params = {"query": "CONTRACT:", "maxResults": 8, "include": ["scripts/*.py"]}
    first = send_rpc(sock, token, "search.literal", params, request_timeout=30.0)
    second = send_rpc(sock, token, "search.literal", params, request_timeout=30.0)
    assert first.get("ok") and second.get("ok")
    rows1 = [(r["path"], r["line"], r["column"]) for r in first["result"]["results"]]
    rows2 = [(r["path"], r["line"], r["column"]) for r in second["result"]["results"]]
    assert rows1 == rows2


def test_live_search_tokens_contract(sock: socket.socket, token: str) -> None:
    response = send_rpc(
        sock,
        token,
        "search.tokens",
        {"query": "SEARCH_LITERAL_RESPONSE_KEYS frozenset", "maxResults": 5, "include": ["scripts/agent_contracts.py"]},
        request_timeout=30.0,
    )
    assert response.get("ok"), response
    result = response["result"]
    errors = validate_search_tokens_response(result)
    assert not errors, errors
    _no_ranking_fields(result)


def test_live_search_tokens_truncation(sock: socket.socket, token: str) -> None:
    response = send_rpc(
        sock,
        token,
        "search.tokens",
        {"query": "def", "maxResults": 2, "include": ["scripts/*.py"]},
        request_timeout=30.0,
    )
    assert response.get("ok"), response
    result = response["result"]
    assert len(result["results"]) <= 2
    assert "truncated" in result
    assert "hasMore" in result
    assert "nextResultOffset" in result
    _no_ranking_fields(result)


def test_live_search_semantic_quarantined(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "search.semantic", {"query": "anything"}, request_timeout=30.0)
    assert response.get("ok") is False, response
    error = response["error"]
    assert error.get("string_code") == "semantic_disabled"
    assert error.get("code") == 4008
    assert_rpc_error_diagnostics(error)
    assert error.get("recovery_hint") == "use_search_literal_or_search_tokens"
    assert error["string_code"] in SEMANTIC_QUARANTINE_ERROR_CODES


def test_live_analysis_search_ranked_quarantined(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "analysis.searchRanked", {"query": "foo"}, request_timeout=30.0)
    assert response.get("ok") is False, response
    error = response["error"]
    assert error.get("string_code") == "ranked_search_disabled"
    assert error.get("code") == 4008
    assert_rpc_error_diagnostics(error)


def test_live_tool_registry(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "tool.registry", {}, request_timeout=30.0)
    assert response.get("ok"), response
    errors = validate_tool_registry_response(response["result"])
    assert not errors, errors
    methods = {entry["method"] for entry in response["result"]["tools"]}
    assert "search.literal" in methods
    semantic = next(e for e in response["result"]["tools"] if e["method"] == "search.semantic")
    assert semantic["deprecated"] is True
    assert semantic["agentSafe"] is False
    assert semantic.get("replacementMethod") == "search.literal"


def test_live_tool_capabilities(sock: socket.socket, token: str) -> None:
    response = send_rpc(sock, token, "tool.capabilities", {}, request_timeout=30.0)
    assert response.get("ok"), response
    errors = validate_tool_capabilities_response(response["result"])
    assert not errors, errors
    assert response["result"]["semanticSearchDisabled"] is True


def test_live_fixture_workspace_order_invariant(sock: socket.socket, token: str) -> None:
    with tempfile.TemporaryDirectory(prefix="retrieval-order-") as tmp:
        root = Path(tmp)
        (root / "alpha.py").write_text("TOKEN_ALPHA marker\n", encoding="utf-8")
        (root / "beta.py").write_text("TOKEN_BETA marker\n", encoding="utf-8")
        (root / "mixed.py").write_text("TOKEN_ALPHA TOKEN_BETA\n", encoding="utf-8")
        open_resp = send_rpc(sock, token, "workspace.openFolder", {"path": str(root)})
        assert open_resp.get("ok"), open_resp
        try:
            literal = send_rpc(sock, token, "search.literal", {"query": "TOKEN_ALPHA", "maxResults": 10})
            assert literal.get("ok"), literal
            paths = [r["path"] for r in literal["result"]["results"]]
            assert paths == sorted(paths)
            tokens = send_rpc(sock, token, "search.tokens", {"query": "TOKEN_ALPHA TOKEN_BETA", "maxResults": 10})
            assert tokens.get("ok"), tokens
            for row in tokens["result"]["results"]:
                assert row.get("matchReason") == "all_tokens_literal"
        finally:
            repo = str(REPO_ROOT)
            send_rpc(sock, token, "workspace.openFolder", {"path": repo})


def main() -> int:
    parser = argparse.ArgumentParser(description="Pass V deterministic retrieval regression suite.")
    add_output_args(parser)
    args = parser.parse_args()
    recorder = CheckRecorder(compact=output_compact(args), verbose=args.verbose)

    for name, fn in [
        ("retrieval.literal_golden", test_offline_literal_golden_fixture),
        ("retrieval.tokens_golden", test_offline_tokens_golden_fixture),
        ("retrieval.semantic_disabled_golden", test_offline_semantic_disabled_golden_fixture),
        ("retrieval.tool_registry_golden", test_offline_tool_registry_golden_fixture),
        ("retrieval.truncation_golden", test_offline_truncation_golden_fixture),
    ]:
        recorder.run(name, fn)

    try:
        with connect() as sock:
            token = load_token()
            workspace_root = ensure_workspace_root(sock, token)
            recorder.record("retrieval.workspace_ready", bool(workspace_root), {"path": workspace_root})
    except Exception as exc:
        recorder.record("retrieval.workspace_ready", False, {"error": str(exc)})
        return recorder.finish("deterministic_retrieval")

    live_checks: list[tuple[str, Callable[[socket.socket, str], None]]] = [
        ("retrieval.search_literal_contract", test_live_search_literal_contract),
        ("retrieval.search_literal_stable_order", test_live_search_literal_stable_order),
        ("retrieval.search_tokens_contract", test_live_search_tokens_contract),
        ("retrieval.search_tokens_truncation", test_live_search_tokens_truncation),
        ("retrieval.semantic_quarantined", test_live_search_semantic_quarantined),
        ("retrieval.ranked_search_quarantined", test_live_analysis_search_ranked_quarantined),
        ("retrieval.tool_registry", test_live_tool_registry),
        ("retrieval.tool_capabilities", test_live_tool_capabilities),
        ("retrieval.fixture_workspace_order", test_live_fixture_workspace_order_invariant),
    ]
    for name, fn in live_checks:
        def _run(f: Callable[[socket.socket, str], None] = fn) -> None:
            with connect() as sock:
                f(sock, load_token())

        recorder.run(name, _run)

    return recorder.finish("deterministic_retrieval")


if __name__ == "__main__":
    raise SystemExit(main())

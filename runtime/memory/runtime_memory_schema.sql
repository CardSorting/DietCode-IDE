-- BroccoliQ-native runtime memory schema (DietCode agent runtime Pass VII)
-- Authority: C++ mutation kernel decides correctness; this layer records history only.

PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS runtime_operations (
    operation_id TEXT PRIMARY KEY,
    method TEXT NOT NULL,
    params_hash TEXT NOT NULL,
    idempotency_key TEXT,
    started_at REAL NOT NULL,
    completed_at REAL,
    status TEXT NOT NULL,
    error_code TEXT,
    recovery_hint TEXT,
    next_recommended_command TEXT,
    revision_before INTEGER,
    revision_after INTEGER,
    receipt_hash TEXT,
    receipt_json TEXT,
    workspace_path TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_runtime_ops_idempotency
    ON runtime_operations(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_runtime_ops_revision
    ON runtime_operations(workspace_path, revision_after);
CREATE INDEX IF NOT EXISTS idx_runtime_ops_recent
    ON runtime_operations(workspace_path, completed_at DESC);

CREATE TABLE IF NOT EXISTS runtime_replay_cache (
    idempotency_key TEXT PRIMARY KEY,
    method TEXT NOT NULL,
    params_hash TEXT NOT NULL,
    result_json TEXT NOT NULL,
    receipt_hash TEXT NOT NULL,
    created_at REAL NOT NULL,
    expires_at REAL NOT NULL,
    eviction_reason TEXT,
    workspace_path TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_runtime_replay_expires
    ON runtime_replay_cache(workspace_path, expires_at);

CREATE TABLE IF NOT EXISTS runtime_revisions (
    revision_id INTEGER NOT NULL,
    workspace_path TEXT NOT NULL,
    changed_files_json TEXT NOT NULL,
    mutation_source TEXT NOT NULL,
    operation_id TEXT,
    receipt_hash TEXT,
    timestamp REAL NOT NULL,
    previous_revision_id INTEGER,
    PRIMARY KEY (workspace_path, revision_id)
);

CREATE TABLE IF NOT EXISTS runtime_workflows (
    workflow_id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at REAL NOT NULL,
    completed_at REAL,
    recovery_hint TEXT,
    next_recommended_command TEXT,
    workspace_path TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS runtime_workflow_steps (
    step_id TEXT PRIMARY KEY,
    workflow_id TEXT NOT NULL,
    command TEXT NOT NULL,
    status TEXT NOT NULL,
    input_hash TEXT,
    output_hash TEXT,
    recovery_hint TEXT,
    next_recommended_command TEXT,
    linked_operation_id TEXT,
    linked_revision_id INTEGER,
    timestamp REAL NOT NULL,
    FOREIGN KEY(workflow_id) REFERENCES runtime_workflows(workflow_id)
);

CREATE TABLE IF NOT EXISTS runtime_verification_runs (
    run_id TEXT PRIMARY KEY,
    command TEXT NOT NULL,
    suite_name TEXT NOT NULL,
    passed_count INTEGER NOT NULL,
    failed_count INTEGER NOT NULL,
    duration_ms REAL NOT NULL,
    failure_summary TEXT,
    timestamp REAL NOT NULL,
    revision_id INTEGER,
    operation_id TEXT,
    workspace_path TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS runtime_telemetry_events (
    event_id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    timestamp REAL NOT NULL,
    dropped INTEGER NOT NULL DEFAULT 0,
    workspace_path TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS runtime_error_events (
    event_id TEXT PRIMARY KEY,
    string_code TEXT NOT NULL,
    recovery_hint TEXT,
    method TEXT,
    timestamp REAL NOT NULL,
    envelope_json TEXT NOT NULL,
    workspace_path TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS runtime_checkpoint (
    key TEXT PRIMARY KEY,
    value_json TEXT NOT NULL,
    updated_at REAL NOT NULL
);

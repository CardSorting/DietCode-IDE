/** Public bridge types — no raw RPC method names in agent-facing surfaces. */

export type BridgeErrorCode =
  | 'stale_content'
  | 'semantic_disabled'
  | 'ranked_search_disabled'
  | 'symlink_target'
  | 'patch_failed'
  | 'nested_call_timeout'
  | 'runtime_unavailable'
  | 'unsupported_runtime_capability'
  | 'transport_error'
  | 'invalid_params'
  | 'approval_required'
  | 'approval_invalid'
  | 'approval_rejected'
  | 'approval_timeout'
  | 'workspace_drift'
  | 'coherence_mismatch'
  | 'unknown';

export type RecoverySource = 'runtime' | 'bridge_fallback';

export type HashAuthority = 'live_validate' | 'live_stat';

export interface BridgeError {
  code: BridgeErrorCode;
  message: string;
  recoveryHint: string;
  nextRecommendedCommand: string;
  retrySafe: boolean;
  recoverySource: RecoverySource;
  nextCommandSource: RecoverySource;
  rawError?: Record<string, unknown>;
}

export interface BridgeEnvelope<T> {
  ok: boolean;
  data?: T;
  error?: BridgeError;
}

export interface PartialResultMeta {
  complete: boolean;
  partial: boolean;
  warnings: string[];
  fallbackUsed: boolean;
  truncated: boolean;
  recoveryHint?: string;
  nextRecommendedCommand?: string;
  raw?: Record<string, unknown>;
}

export interface BridgeResult<T> extends PartialResultMeta {
  result: T;
}

export interface RuntimeCapabilities {
  deterministicSearch: boolean;
  patchReceipts: boolean;
  batchReceipts: boolean;
  runtimeTimeline: boolean;
  broccoliqJournal: boolean;
  operationStatus: boolean;
  partialSuccessEnvelopes: boolean;
}

export interface RuntimeProfile {
  connected: boolean;
  contractVersion: string;
  schemaVersion: string;
  capabilities: RuntimeCapabilities;
  agentSafeMethodCount: number;
  semanticSearchDisabled: boolean;
  rankingPolicy: string;
  diagnosticsAvailable: boolean;
  workspacePath?: string;
  mutationAuthority?: string;
  recordAuthority?: string;
}

export interface MutationReceipt {
  path: string;
  beforeContentHash: string;
  postContentHash: string;
  patchFingerprint: string;
  readSourceBefore: string;
  applyChannel: string;
  atomic: boolean;
}

export interface BatchMutationReceipt {
  atomic: boolean;
  appliedCount: number;
  rolledBack: boolean;
  fileReceipts: MutationReceipt[];
  rollbackProof?: Record<string, unknown>;
}

export interface SafePatchSuccess {
  applied: true;
  mutationReceipt: MutationReceipt;
  revisionBefore?: number;
  revisionAfter?: number;
  idempotencyKey: string;
  nextRecommendedCommand?: string;
  beforeHashSource: HashAuthority;
  beforeContentHash: string;
}

export interface StalePatchRecovery {
  applied: false;
  stale: true;
  path: string;
  expectedBeforeHash: string;
  currentContentHash?: string;
  recoveryHint: string;
  nextRecommendedCommand: string;
  recoverySource: RecoverySource;
  nextCommandSource: RecoverySource;
  idempotencyKey: string;
}

export interface CoherenceStaleRecovery {
  applied: false;
  coherenceStale: true;
  operatorInterventionRequired: false;
  path: string;
  reason: string;
  changedPaths: string[];
  recoveryHint: string;
  nextRecommendedCommand: string;
  recoverySource: RecoverySource;
  nextCommandSource: RecoverySource;
  idempotencyKey: string;
}

export interface CoherenceOperatorRequired {
  applied: false;
  coherenceStale: true;
  operatorInterventionRequired: true;
  path: string;
  reason: string;
  changedPaths: string[];
  recoveryHint: string;
  nextRecommendedCommand: string;
  recoverySource: RecoverySource;
  nextCommandSource: RecoverySource;
  idempotencyKey: string;
}

export type SafePatchResult =
  | SafePatchSuccess
  | StalePatchRecovery
  | CoherenceStaleRecovery
  | CoherenceOperatorRequired;

export interface SafeBatchPatchSuccess {
  applied: true;
  atomic: true;
  batchMutationReceipt: BatchMutationReceipt;
  idempotencyKey: string;
  revisionBefore?: number;
  revisionAfter?: number;
  nextRecommendedCommand?: string;
}

export interface SafeBatchPatchFailure {
  applied: false;
  atomic: true;
  rolledBack: true;
  stale?: boolean;
  coherenceStale?: boolean;
  operatorInterventionRequired?: boolean;
  reason?: string;
  changedPaths?: string[];
  failedPath?: string;
  idempotencyKey: string;
  recoveryHint: string;
  nextRecommendedCommand: string;
  filesVerifiedUnchanged: boolean;
}

export type SafeBatchPatchResult = SafeBatchPatchSuccess | SafeBatchPatchFailure;

export interface PatchBatchEntry {
  path: string;
  unifiedDiff: string;
}

export interface SearchOptions {
  maxResults?: number;
  caseSensitive?: boolean;
  include?: string[];
  exclude?: string[];
  includeRaw?: boolean;
}

export interface CoherenceToken {
  tokenId: string;
  workspaceRevision: number;
  verifyRevision: number;
  anchors: Record<string, string>;
}

export type CoherenceRecoveryEventType =
  | 'context.stale'
  | 'context.refreshed'
  | 'coherence.retry'
  | 'coherence.operator_required';

export interface CoherenceRecoveryEvent {
  type: CoherenceRecoveryEventType;
  path: string;
  taskId?: string;
  reason?: string;
  changedPaths?: string[];
  attempt?: number;
  tokenId?: string;
}

export interface PatchOptions {
  dryRun?: boolean;
  idempotencyKey?: string;
  requestTimeoutMs?: number;
  includeRaw?: boolean;
  taskId?: string;
  coherenceTokenId?: string;
  expectedWorkspaceRevision?: number;
  lineReplacement?: { search: string; replace: string };
  /** Rebuild unified diff from live file content after coherence_mismatch. */
  buildPatchFromContent?: (args: { path: string; content: string }) => string;
  /** NDJSON-style recovery telemetry for governed tasks. */
  onCoherenceEvent?: (event: CoherenceRecoveryEvent) => void;
}

export interface BatchPatchOptions extends PatchOptions {
  confirm?: boolean;
}

export interface TimelineOptions {
  limit?: number;
  offset?: number;
  sinceRevision?: number;
  errorsOnly?: boolean;
  includeRaw?: boolean;
}

export interface ActivityOptions {
  limit?: number;
  sinceRevision?: number;
  includeRaw?: boolean;
}

export interface OperationStatusResult {
  status: 'completed' | 'unknown' | 'pending';
  idempotencyKey: string;
  revisionBefore?: number;
  revisionAfter?: number;
  changedFiles?: string[];
  mutationReceipt?: MutationReceipt;
  batchMutationReceipt?: BatchMutationReceipt;
  completedAt?: string;
  recordAuthority?: string;
  mutationAuthority?: string;
  currentStateAuthority?: string;
  notCurrentFileTruth?: boolean;
}

export interface VerifyFastResult {
  ok: boolean;
  rpcReady: boolean;
  runtimeAvailable: boolean;
  latencyMs: number;
}

export interface RpcEnvelope {
  id: string;
  ok: boolean;
  result?: Record<string, unknown>;
  error?: RpcErrorPayload;
  _clientDurationMs?: number;
}

export interface RpcErrorPayload {
  code: number;
  string_code?: string;
  message: string;
  recovery_hint?: string;
  nextRecommendedCommand?: string;
  retryable?: boolean;
  category?: string;
}

export interface TransportOptions {
  socketPath?: string;
  tokenPath?: string;
  schemaVersion?: string;
  requestTimeoutMs?: number;
  connectTimeoutMs?: number;
  transportRetries?: number;
  startApp?: boolean;
  appPath?: string;
  agentId?: string;
  rationale?: string;
  workspaceRoot?: string;
  ensureWorkspace?: boolean;
}

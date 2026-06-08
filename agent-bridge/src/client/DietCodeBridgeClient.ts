import { ensureWorkspaceRoot } from '../adapters/workspaceAdapter.js';
import { detectRuntimeCapabilities } from '../capabilities/detectRuntimeCapabilities.js';
import { fetchDiagnostics, fetchFileStat } from '../adapters/diagnosticsAdapter.js';
import { searchLiteral, searchPaths, searchTokens } from '../adapters/searchAdapter.js';
import {
  fetchOperationStatus,
  fetchRecentActivity,
  fetchTimeline,
  verifyFast,
} from '../adapters/runtimeAdapter.js';
import { safePatchBatch } from '../workflows/safePatchBatch.js';
import { safePatchFile } from '../workflows/safePatchFile.js';
import { resolveConnectOptions, waitForReady } from './connection.js';
import { RpcTransport } from './RpcTransport.js';
import { DietCodeBridgeError } from '../contracts/BridgeError.js';
import type {
  ActivityOptions,
  BatchPatchOptions,
  BridgeResult,
  OperationStatusResult,
  PatchBatchEntry,
  PatchOptions,
  RuntimeProfile,
  SafeBatchPatchResult,
  SafePatchResult,
  SearchOptions,
  TimelineOptions,
  TransportOptions,
  VerifyFastResult,
} from '../contracts/types.js';

export class DietCodeBridgeClient {
  private readonly transport: RpcTransport;
  private profile: RuntimeProfile | null = null;
  private workspacePath: string | undefined;
  private readonly defaultOptions: TransportOptions;

  constructor(options: TransportOptions = {}) {
    this.defaultOptions = resolveConnectOptions(options);
    this.transport = new RpcTransport(this.defaultOptions);
  }

  /** Establish transport, wait for RPC readiness, detect capabilities, optionally open workspace. */
  async connect(options: TransportOptions = {}): Promise<RuntimeProfile> {
    const merged = { ...this.defaultOptions, ...resolveConnectOptions(options) };
    await this.transport.connect(merged);
    await waitForReady(this.transport, { timeoutMs: merged.connectTimeoutMs });
    this.profile = await detectRuntimeCapabilities(this.transport);

    if (merged.ensureWorkspace !== false) {
      this.workspacePath = await ensureWorkspaceRoot(this.transport, merged.workspaceRoot);
      if (this.profile) {
        this.profile = { ...this.profile, workspacePath: this.workspacePath };
      }
    }

    return this.profile;
  }

  async reconnect(options: TransportOptions = {}): Promise<RuntimeProfile> {
    await this.transport.reconnect(resolveConnectOptions({ ...this.defaultOptions, ...options }));
    return this.connect(options);
  }

  async close(): Promise<void> {
    await this.transport.close();
    this.profile = null;
    this.workspacePath = undefined;
  }

  async [Symbol.asyncDispose](): Promise<void> {
    await this.close();
  }

  getRuntimeProfile(): RuntimeProfile {
    if (!this.profile) {
      throw new DietCodeBridgeError(
        'runtime_unavailable',
        'bridge not connected — call connect() first',
      );
    }
    return this.profile;
  }

  getWorkspacePath(): string | undefined {
    return this.workspacePath;
  }

  async getDiagnostics(includeRaw = false): Promise<BridgeResult<Record<string, unknown>>> {
    return fetchDiagnostics(this.transport, includeRaw);
  }

  async searchLiteral(
    query: string,
    options?: SearchOptions,
  ): Promise<BridgeResult<Record<string, unknown>>> {
    return searchLiteral(this.transport, query, options);
  }

  async searchTokens(
    tokens: string[],
    options?: SearchOptions,
  ): Promise<BridgeResult<Record<string, unknown>>> {
    return searchTokens(this.transport, tokens, options);
  }

  async searchPaths(
    query: string,
    options?: SearchOptions,
  ): Promise<BridgeResult<Record<string, unknown>>> {
    return searchPaths(this.transport, query, options);
  }

  async getFileStat(
    path: string,
    includeRaw = false,
  ): Promise<BridgeResult<Record<string, unknown>>> {
    return fetchFileStat(this.transport, path, includeRaw);
  }

  async safePatchFile(
    path: string,
    unifiedDiff: string,
    options?: PatchOptions,
  ): Promise<SafePatchResult> {
    return safePatchFile(this.transport, path, unifiedDiff, options);
  }

  async safePatchBatch(
    patches: PatchBatchEntry[],
    options?: BatchPatchOptions,
  ): Promise<SafeBatchPatchResult> {
    return safePatchBatch(this.transport, patches, options);
  }

  async getOperationStatus(idempotencyKey: string): Promise<OperationStatusResult> {
    return fetchOperationStatus(this.transport, idempotencyKey);
  }

  async getTimeline(options?: TimelineOptions): Promise<BridgeResult<Record<string, unknown>>> {
    return fetchTimeline(this.transport, options);
  }

  async getRecentActivity(
    options?: ActivityOptions,
  ): Promise<BridgeResult<Record<string, unknown>>> {
    return fetchRecentActivity(this.transport, options);
  }

  async verifyFast(): Promise<VerifyFastResult> {
    return verifyFast(this.transport);
  }
}

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
import { RpcTransport } from './RpcTransport.js';
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

  constructor(options: TransportOptions = {}) {
    this.transport = new RpcTransport(options);
  }

  /** Establish transport and detect runtime capabilities. */
  async connect(options: TransportOptions = {}): Promise<RuntimeProfile> {
    await this.transport.connect(options);
    this.profile = await detectRuntimeCapabilities(this.transport);
    return this.profile;
  }

  async close(): Promise<void> {
    await this.transport.close();
    this.profile = null;
  }

  getRuntimeProfile(): RuntimeProfile {
    if (!this.profile) {
      throw new Error('bridge not connected — call connect() first');
    }
    return this.profile;
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

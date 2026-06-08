import { ensureWorkspaceRoot } from '../adapters/workspaceAdapter.js';
import { detectRuntimeCapabilities } from '../capabilities/detectRuntimeCapabilities.js';
import { fetchDiagnostics, fetchFileStat } from '../adapters/diagnosticsAdapter.js';
import { searchLiteral, searchPaths, searchTokens } from '../adapters/searchAdapter.js';
import { fetchOperationStatus, fetchRecentActivity, fetchTimeline, verifyFast, } from '../adapters/runtimeAdapter.js';
import { shellCatSmall, shellCd, shellHead, shellPwd, shellRg, shellSedRange, shellTail, } from '../adapters/shellAdapter.js';
import { safePatchBatch } from '../workflows/safePatchBatch.js';
import { safePatchFile } from '../workflows/safePatchFile.js';
import { resolveConnectOptions, waitForReady } from './connection.js';
import { RpcTransport } from './RpcTransport.js';
import { DietCodeBridgeError } from '../contracts/BridgeError.js';
export class DietCodeBridgeClient {
    transport;
    profile = null;
    workspacePath;
    defaultOptions;
    constructor(options = {}) {
        this.defaultOptions = resolveConnectOptions(options);
        this.transport = new RpcTransport(this.defaultOptions);
    }
    /** Establish transport, wait for RPC readiness, detect capabilities, optionally open workspace. */
    async connect(options = {}) {
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
    async reconnect(options = {}) {
        await this.transport.reconnect(resolveConnectOptions({ ...this.defaultOptions, ...options }));
        return this.connect(options);
    }
    async close() {
        await this.transport.close();
        this.profile = null;
        this.workspacePath = undefined;
    }
    async [Symbol.asyncDispose]() {
        await this.close();
    }
    getRuntimeProfile() {
        if (!this.profile) {
            throw new DietCodeBridgeError('runtime_unavailable', 'bridge not connected — call connect() first');
        }
        return this.profile;
    }
    getWorkspacePath() {
        return this.workspacePath;
    }
    async getDiagnostics(includeRaw = false) {
        return fetchDiagnostics(this.transport, includeRaw);
    }
    async searchLiteral(query, options) {
        return searchLiteral(this.transport, query, options);
    }
    async searchTokens(tokens, options) {
        return searchTokens(this.transport, tokens, options);
    }
    async searchPaths(query, options) {
        return searchPaths(this.transport, query, options);
    }
    async getFileStat(path, includeRaw = false) {
        return fetchFileStat(this.transport, path, includeRaw);
    }
    async safePatchFile(path, unifiedDiff, options) {
        return safePatchFile(this.transport, path, unifiedDiff, options);
    }
    async safePatchBatch(patches, options) {
        return safePatchBatch(this.transport, patches, options);
    }
    async getOperationStatus(idempotencyKey) {
        return fetchOperationStatus(this.transport, idempotencyKey);
    }
    async getTimeline(options) {
        return fetchTimeline(this.transport, options);
    }
    async getRecentActivity(options) {
        return fetchRecentActivity(this.transport, options);
    }
    async verifyFast() {
        return verifyFast(this.transport);
    }
    async shellPwd() {
        return shellPwd(this.transport);
    }
    async shellCd(path) {
        return shellCd(this.transport, path);
    }
    async shellRg(pattern, options) {
        return shellRg(this.transport, pattern, options);
    }
    async shellHead(path, lines) {
        return shellHead(this.transport, path, lines);
    }
    async shellTail(path, lines) {
        return shellTail(this.transport, path, lines);
    }
    async shellSedRange(path, startLine, endLine) {
        return shellSedRange(this.transport, path, startLine, endLine);
    }
    async shellCatSmall(path) {
        return shellCatSmall(this.transport, path);
    }
}
//# sourceMappingURL=DietCodeBridgeClient.js.map
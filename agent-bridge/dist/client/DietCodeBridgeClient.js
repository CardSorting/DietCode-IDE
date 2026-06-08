import { detectRuntimeCapabilities } from '../capabilities/detectRuntimeCapabilities.js';
import { fetchDiagnostics, fetchFileStat } from '../adapters/diagnosticsAdapter.js';
import { searchLiteral, searchPaths, searchTokens } from '../adapters/searchAdapter.js';
import { fetchOperationStatus, fetchRecentActivity, fetchTimeline, verifyFast, } from '../adapters/runtimeAdapter.js';
import { safePatchBatch } from '../workflows/safePatchBatch.js';
import { safePatchFile } from '../workflows/safePatchFile.js';
import { RpcTransport } from './RpcTransport.js';
export class DietCodeBridgeClient {
    transport;
    profile = null;
    constructor(options = {}) {
        this.transport = new RpcTransport(options);
    }
    /** Establish transport and detect runtime capabilities. */
    async connect(options = {}) {
        await this.transport.connect(options);
        this.profile = await detectRuntimeCapabilities(this.transport);
        return this.profile;
    }
    async close() {
        await this.transport.close();
        this.profile = null;
    }
    getRuntimeProfile() {
        if (!this.profile) {
            throw new Error('bridge not connected — call connect() first');
        }
        return this.profile;
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
}
//# sourceMappingURL=DietCodeBridgeClient.js.map
import { mapRpcError } from '../contracts/errors.js';
import { normalizeRpcSuccess } from '../contracts/schemas.js';
export async function searchLiteral(transport, query, options = {}) {
    const envelope = await transport.call('search.literal', {
        query,
        maxResults: options.maxResults ?? 50,
        caseSensitive: options.caseSensitive ?? false,
        include: options.include,
        exclude: options.exclude,
    });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'searchLiteral');
    }
    return normalizeRpcSuccess(envelope, options.includeRaw);
}
export async function searchTokens(transport, tokens, options = {}) {
    const envelope = await transport.call('search.tokens', {
        tokens,
        maxResults: options.maxResults ?? 50,
        caseSensitive: options.caseSensitive ?? false,
        include: options.include,
        exclude: options.exclude,
    });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'searchTokens');
    }
    return normalizeRpcSuccess(envelope, options.includeRaw);
}
export async function searchPaths(transport, query, options = {}) {
    const envelope = await transport.call('search.paths', {
        query,
        maxResults: options.maxResults ?? 50,
        include: options.include,
        exclude: options.exclude,
    });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'searchPaths');
    }
    return normalizeRpcSuccess(envelope, options.includeRaw);
}
//# sourceMappingURL=searchAdapter.js.map
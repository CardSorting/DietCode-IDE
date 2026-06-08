import { mapRpcError } from '../contracts/errors.js';
import { normalizeRpcSuccess } from '../contracts/schemas.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { BridgeResult, SearchOptions } from '../contracts/types.js';

export async function searchLiteral(
  transport: RpcCaller,
  query: string,
  options: SearchOptions = {},
): Promise<BridgeResult<Record<string, unknown>>> {
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

export async function searchTokens(
  transport: RpcCaller,
  tokens: string[],
  options: SearchOptions = {},
): Promise<BridgeResult<Record<string, unknown>>> {
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

export async function searchPaths(
  transport: RpcCaller,
  query: string,
  options: SearchOptions = {},
): Promise<BridgeResult<Record<string, unknown>>> {
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

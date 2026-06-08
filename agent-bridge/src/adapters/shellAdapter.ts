import type { RpcCaller } from '../client/RpcTransport.js';
import { mapRpcError } from '../contracts/errors.js';
import { normalizeRpcSuccess } from '../contracts/schemas.js';
import type { BridgeResult } from '../contracts/types.js';

export interface ShellRgOptions {
  path?: string;
  maxResults?: number;
  include?: string[];
  exclude?: string[];
  hidden?: boolean;
  regex?: boolean;
}

async function callShell(
  transport: RpcCaller,
  method: string,
  params: Record<string, unknown>,
  label: string,
): Promise<BridgeResult<Record<string, unknown>>> {
  const envelope = await transport.call(method, params);
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, label);
  }
  return normalizeRpcSuccess(envelope);
}

export async function shellPwd(
  transport: RpcCaller,
): Promise<BridgeResult<Record<string, unknown>>> {
  return callShell(transport, 'shell.pwd', {}, 'shellPwd');
}

export async function shellCd(
  transport: RpcCaller,
  path: string,
): Promise<BridgeResult<Record<string, unknown>>> {
  return callShell(transport, 'shell.cd', { path }, 'shellCd');
}

export async function shellRg(
  transport: RpcCaller,
  pattern: string,
  options: ShellRgOptions = {},
): Promise<BridgeResult<Record<string, unknown>>> {
  return callShell(
    transport,
    'shell.rg',
    {
      pattern,
      ...options,
    },
    'shellRg',
  );
}

export async function shellHead(
  transport: RpcCaller,
  path: string,
  lines?: number,
): Promise<BridgeResult<Record<string, unknown>>> {
  return callShell(transport, 'shell.head', { path, ...(lines ? { lines } : {}) }, 'shellHead');
}

export async function shellTail(
  transport: RpcCaller,
  path: string,
  lines?: number,
): Promise<BridgeResult<Record<string, unknown>>> {
  return callShell(transport, 'shell.tail', { path, ...(lines ? { lines } : {}) }, 'shellTail');
}

export async function shellSedRange(
  transport: RpcCaller,
  path: string,
  startLine: number,
  endLine: number,
): Promise<BridgeResult<Record<string, unknown>>> {
  return callShell(transport, 'shell.sedRange', { path, startLine, endLine }, 'shellSedRange');
}

export async function shellCatSmall(
  transport: RpcCaller,
  path: string,
): Promise<BridgeResult<Record<string, unknown>>> {
  return callShell(transport, 'shell.catSmall', { path }, 'shellCatSmall');
}

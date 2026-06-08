import type { RpcCaller } from '../client/RpcTransport.js';
export declare function getWorkspaceRoot(transport: RpcCaller): Promise<string | undefined>;
export declare function openWorkspaceFolder(transport: RpcCaller, path: string): Promise<string>;
export declare function ensureWorkspaceRoot(transport: RpcCaller, preferredRoot?: string): Promise<string>;
//# sourceMappingURL=workspaceAdapter.d.ts.map
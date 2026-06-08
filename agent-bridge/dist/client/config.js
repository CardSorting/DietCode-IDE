import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
export const CLIENT_SCHEMA_VERSION = '1.6.2';
export const BRIDGE_PACKAGE_VERSION = '1.0.0';
export const DEFAULT_SOCKET_PATH = join(homedir(), '.dietcode', 'control.sock');
export const DEFAULT_TOKEN_PATH = join(homedir(), '.dietcode', 'session.token');
export const MAX_REQUEST_BYTES = 1024 * 1024;
export const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;
const READ_METHODS = new Set([
    'rpc.ping',
    'rpc.version',
    'rpc.methods',
    'rpc.describe',
    'tool.capabilities',
    'tool.registry',
    'runtime.diagnostics',
    'runtime.timeline',
    'runtime.history',
    'workspace.activity',
    'workspace.getRoot',
    'workspace.revision',
    'workspace.snapshot',
    'operation.status',
    'search.literal',
    'search.tokens',
    'search.paths',
    'search.files',
    'file.stat',
    'patch.validate',
    'shell.pwd',
    'shell.cd',
    'shell.rg',
    'shell.head',
    'shell.tail',
    'shell.sedRange',
    'shell.catSmall',
]);
export function isReadMethod(method) {
    return READ_METHODS.has(method);
}
export function resolveTransportConfig(options = {}) {
    return {
        socketPath: options.socketPath ?? DEFAULT_SOCKET_PATH,
        tokenPath: options.tokenPath ?? DEFAULT_TOKEN_PATH,
        schemaVersion: options.schemaVersion ?? CLIENT_SCHEMA_VERSION,
        appPath: resolveAppPath(options.appPath),
        startApp: options.startApp !== false,
        connectTimeoutMs: options.connectTimeoutMs ?? 10_000,
        requestTimeoutMs: options.requestTimeoutMs ?? 30_000,
        transportRetries: Math.max(0, options.transportRetries ?? 1),
        agentId: options.agentId,
        rationale: options.rationale,
        workspaceRoot: options.workspaceRoot,
    };
}
export function resolveAppPath(explicit) {
    if (explicit) {
        return resolve(explicit);
    }
    const fromEnv = process.env.DIETCODE_APP_PATH;
    if (fromEnv) {
        return resolve(fromEnv);
    }
    const bundled = resolveBundledAppBinary();
    if (bundled) {
        return bundled;
    }
    const repoCandidate = resolve(process.cwd(), 'build/DietCode.app/Contents/MacOS/DietCode');
    if (existsSync(repoCandidate)) {
        return repoCandidate;
    }
    return undefined;
}
function resolveBundledAppBinary() {
    try {
        const entry = process.argv[1];
        if (!entry) {
            return undefined;
        }
        const cliDir = dirname(resolve(entry));
        const fromBinLauncher = resolve(cliDir, '../../MacOS/DietCode');
        if (existsSync(fromBinLauncher)) {
            return fromBinLauncher;
        }
        const fromBridgeBundle = resolve(cliDir, '../../../MacOS/DietCode');
        if (existsSync(fromBridgeBundle)) {
            return fromBridgeBundle;
        }
    }
    catch {
        return undefined;
    }
    try {
        const moduleDir = dirname(fileURLToPath(import.meta.url));
        const fromModule = resolve(moduleDir, '../../../../MacOS/DietCode');
        if (existsSync(fromModule)) {
            return fromModule;
        }
    }
    catch {
        return undefined;
    }
    return undefined;
}
//# sourceMappingURL=config.js.map
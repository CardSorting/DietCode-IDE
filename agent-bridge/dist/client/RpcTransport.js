import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { bridgeError } from '../contracts/errors.js';
export const CLIENT_SCHEMA_VERSION = '1.6.2';
export const DEFAULT_SOCKET_PATH = join(homedir(), '.dietcode', 'control.sock');
export const DEFAULT_TOKEN_PATH = join(homedir(), '.dietcode', 'session.token');
const MAX_REQUEST_BYTES = 1024 * 1024;
const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;
export class RpcTransport {
    socket = null;
    buffer = '';
    pending = new Map();
    token = '';
    socketPath;
    tokenPath;
    schemaVersion;
    appPath;
    autoStart;
    defaultTimeoutMs;
    constructor(options = {}) {
        this.socketPath = options.socketPath ?? DEFAULT_SOCKET_PATH;
        this.tokenPath = options.tokenPath ?? DEFAULT_TOKEN_PATH;
        this.schemaVersion = options.schemaVersion ?? CLIENT_SCHEMA_VERSION;
        this.defaultTimeoutMs = options.requestTimeoutMs ?? 30_000;
        this.appPath = options.appPath;
        this.autoStart = options.startApp !== false;
    }
    async connect(options = {}) {
        const shouldStart = options.startApp ?? this.autoStart;
        if (shouldStart) {
            await this.ensureSocket(options.appPath ?? this.appPath);
        }
        this.token = await readFile(this.tokenPath, 'utf8').then((t) => t.trim());
        this.socket = net.createConnection(this.socketPath);
        this.socket.setEncoding('utf8');
        this.socket.on('data', (chunk) => {
            this.onData(typeof chunk === 'string' ? chunk : chunk.toString('utf8'));
        });
        this.socket.on('error', (err) => this.rejectAll(err));
        this.socket.on('close', () => this.rejectAll(new Error('socket closed')));
        await new Promise((resolve, reject) => {
            const socket = this.socket;
            if (!socket) {
                reject(new Error('socket not created'));
                return;
            }
            socket.once('connect', () => resolve());
            socket.once('error', reject);
        });
    }
    async close() {
        if (this.socket) {
            this.socket.destroy();
            this.socket = null;
        }
        this.pending.clear();
    }
    async call(method, params = {}, options = {}) {
        const socket = this.socket;
        if (!socket) {
            throw bridgeError('transport_error', 'bridge not connected');
        }
        const requestId = options.requestId ?? `${method}:${randomUUID()}`;
        const payload = {
            id: requestId,
            schemaVersion: this.schemaVersion,
            method,
            params,
            token: this.token,
        };
        const encoded = `${JSON.stringify(payload)}\n`;
        if (Buffer.byteLength(encoded, 'utf8') > MAX_REQUEST_BYTES) {
            throw bridgeError('invalid_params', `request exceeds ${MAX_REQUEST_BYTES} bytes`);
        }
        const timeoutMs = options.timeoutMs ?? this.defaultTimeoutMs;
        const started = performance.now();
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                this.pending.delete(requestId);
                reject(bridgeError('nested_call_timeout', `RPC timed out after ${timeoutMs}ms`, {
                    method,
                    requestId,
                }));
            }, timeoutMs);
            this.pending.set(requestId, {
                resolve: (frame) => {
                    clearTimeout(timer);
                    frame._clientDurationMs = Math.round(performance.now() - started);
                    resolve(frame);
                },
                reject: (err) => {
                    clearTimeout(timer);
                    reject(err);
                },
            });
            socket.write(encoded, (err) => {
                if (err) {
                    clearTimeout(timer);
                    this.pending.delete(requestId);
                    reject(bridgeError('transport_error', err.message));
                }
            });
        });
    }
    onData(chunk) {
        this.buffer += chunk;
        let newlineIndex = this.buffer.indexOf('\n');
        while (newlineIndex >= 0) {
            const line = this.buffer.slice(0, newlineIndex).trim();
            this.buffer = this.buffer.slice(newlineIndex + 1);
            if (line) {
                this.dispatchFrame(line);
            }
            newlineIndex = this.buffer.indexOf('\n');
        }
    }
    dispatchFrame(line) {
        if (Buffer.byteLength(line, 'utf8') > MAX_RESPONSE_BYTES) {
            this.rejectAll(new Error('response exceeds maximum allowed size'));
            return;
        }
        let frame;
        try {
            frame = JSON.parse(line);
        }
        catch {
            return;
        }
        const frameId = frame.id;
        if (!frameId) {
            return;
        }
        const waiter = this.pending.get(frameId);
        if (waiter) {
            this.pending.delete(frameId);
            waiter.resolve(frame);
        }
    }
    rejectAll(err) {
        for (const [, waiter] of this.pending) {
            waiter.reject(err);
        }
        this.pending.clear();
    }
    async ensureSocket(appPath) {
        if (await this.socketProbe()) {
            return;
        }
        const binary = appPath ?? process.env.DIETCODE_APP_PATH;
        if (!binary) {
            throw bridgeError('runtime_unavailable', `control socket not available at ${this.socketPath}`);
        }
        await new Promise((resolve, reject) => {
            const child = spawn(binary, ['--ensure-socket'], {
                stdio: 'ignore',
                env: process.env,
            });
            child.on('error', reject);
            child.on('exit', (code) => {
                if (code === 0) {
                    resolve();
                }
                else {
                    reject(bridgeError('runtime_unavailable', `--ensure-socket exited ${code}`));
                }
            });
        });
        const deadline = Date.now() + 10_000;
        while (Date.now() < deadline) {
            if (await this.socketProbe()) {
                return;
            }
            await sleep(200);
        }
        throw bridgeError('runtime_unavailable', `socket not ready at ${this.socketPath}`);
    }
    socketProbe() {
        return new Promise((resolve) => {
            const probe = net.createConnection(this.socketPath);
            probe.setTimeout(500);
            probe.once('connect', () => {
                probe.destroy();
                resolve(true);
            });
            probe.once('error', () => resolve(false));
            probe.once('timeout', () => {
                probe.destroy();
                resolve(false);
            });
        });
    }
}
/** In-memory transport for offline bridge tests. */
export class MockRpcTransport {
    handlers;
    calls = [];
    constructor(handlers = {}) {
        this.handlers = new Map(Object.entries(handlers));
    }
    async connect() {
        return;
    }
    async close() {
        return;
    }
    async call(method, params = {}) {
        this.calls.push({ method, params });
        const handler = this.handlers.get(method);
        if (!handler) {
            return {
                id: `mock:${method}`,
                ok: false,
                error: {
                    code: -32601,
                    string_code: 'method_not_found',
                    message: `no mock for ${method}`,
                },
            };
        }
        return handler(params);
    }
    setHandler(method, handler) {
        this.handlers.set(method, handler);
    }
}
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
export function isBridgeError(value) {
    return (typeof value === 'object' &&
        value !== null &&
        'code' in value &&
        'message' in value &&
        'recoveryHint' in value);
}
//# sourceMappingURL=RpcTransport.js.map
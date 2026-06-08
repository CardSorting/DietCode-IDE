import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import net from 'node:net';
import { spawn } from 'node:child_process';

import { DietCodeBridgeError, isBridgeError } from '../contracts/BridgeError.js';
import type { RpcEnvelope, TransportOptions } from '../contracts/types.js';
import {
  isReadMethod,
  MAX_REQUEST_BYTES,
  MAX_RESPONSE_BYTES,
  resolveTransportConfig,
  type ResolvedTransportConfig,
} from './config.js';

export { CLIENT_SCHEMA_VERSION, DEFAULT_SOCKET_PATH, DEFAULT_TOKEN_PATH } from './config.js';

export interface RpcCaller {
  call(
    method: string,
    params?: Record<string, unknown>,
    options?: { requestId?: string; timeoutMs?: number; agentId?: string; rationale?: string },
  ): Promise<RpcEnvelope>;
  connect(options?: TransportOptions): Promise<void>;
  close(): Promise<void>;
}

export class RpcTransport implements RpcCaller {
  private socket: net.Socket | null = null;
  private buffer = Buffer.alloc(0);
  private token = '';
  private readonly config: ResolvedTransportConfig;
  private callChain: Promise<unknown> = Promise.resolve();
  private closed = false;

  constructor(options: TransportOptions = {}) {
    this.config = resolveTransportConfig(options);
  }

  async connect(options: TransportOptions = {}): Promise<void> {
    const merged = resolveTransportConfig({ ...this.config, ...options });
  Object.assign(this.config, merged);

    if (this.config.startApp) {
      await this.ensureSocket(this.config.appPath);
    }

    this.token = await readFile(this.config.tokenPath, 'utf8').then((t) => t.trim());
    this.socket = net.createConnection(this.config.socketPath);
    this.closed = false;

    await new Promise<void>((resolve, reject) => {
      const socket = this.socket;
      if (!socket) {
        reject(new DietCodeBridgeError('transport_error', 'socket not created'));
        return;
      }
      const timer = setTimeout(() => {
        reject(
          new DietCodeBridgeError(
            'transport_error',
            `socket connect timed out after ${this.config.connectTimeoutMs}ms`,
          ),
        );
      }, this.config.connectTimeoutMs);
      socket.once('connect', () => {
        clearTimeout(timer);
        resolve();
      });
      socket.once('error', (err) => {
        clearTimeout(timer);
        reject(new DietCodeBridgeError('transport_error', err.message));
      });
    });
  }

  async close(): Promise<void> {
    this.closed = true;
    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
    }
    this.buffer = Buffer.alloc(0);
  }

  async reconnect(options: TransportOptions = {}): Promise<void> {
    await this.close();
    await this.connect(options);
  }

  async call(
    method: string,
    params: Record<string, unknown> = {},
    options: { requestId?: string; timeoutMs?: number; agentId?: string; rationale?: string } = {},
  ): Promise<RpcEnvelope> {
    const run = async (): Promise<RpcEnvelope> => this.callUnlocked(method, params, options);
    const chained = this.callChain.then(run, run);
    this.callChain = chained.then(
      () => undefined,
      () => undefined,
    );
    return chained;
  }

  private async callUnlocked(
    method: string,
    params: Record<string, unknown>,
    options: { requestId?: string; timeoutMs?: number; agentId?: string; rationale?: string },
  ): Promise<RpcEnvelope> {
    const maxAttempts = isReadMethod(method)
      ? Math.max(1, this.config.transportRetries)
      : this.config.transportRetries;
    let transportAttempts = 0;
    let tokenRefreshed = false;

    while (true) {
      if (!this.socket || this.closed) {
        await this.reconnect();
      }

      try {
        const frame = await this.sendAndReceive(method, params, options);
        const err = frame.error;
        const message = String(err?.message ?? '').toLowerCase();
        if (
          !frame.ok &&
          err?.string_code === 'permission_denied' &&
          message.includes('token') &&
          !tokenRefreshed
        ) {
          tokenRefreshed = true;
          this.token = await readFile(this.config.tokenPath, 'utf8').then((t) => t.trim());
          continue;
        }
        return frame;
      } catch (error) {
        if (error instanceof DietCodeBridgeError && error.code === 'nested_call_timeout') {
          throw error;
        }

        const transportFailure =
          error instanceof DietCodeBridgeError &&
          (error.code === 'transport_error' || error.code === 'runtime_unavailable');

        if (transportFailure && transportAttempts < maxAttempts) {
          transportAttempts += 1;
          await this.reconnect();
          continue;
        }

        throw error;
      }
    }
  }

  private async sendAndReceive(
    method: string,
    params: Record<string, unknown>,
    options: { requestId?: string; timeoutMs?: number; agentId?: string; rationale?: string },
  ): Promise<RpcEnvelope> {
    const socket = this.socket;
    if (!socket) {
      throw new DietCodeBridgeError('transport_error', 'bridge not connected');
    }

    const requestId = options.requestId ?? `${method}:${randomUUID()}`;
    const payload: Record<string, unknown> = {
      id: requestId,
      schemaVersion: this.config.schemaVersion,
      method,
      params,
      token: this.token,
    };

    const agentId = options.agentId ?? this.config.agentId;
    const rationale = options.rationale ?? this.config.rationale;
    if (agentId) payload.agentId = agentId;
    if (rationale) payload.rationale = rationale;

    const encoded = Buffer.from(`${JSON.stringify(payload)}\n`, 'utf8');
    if (encoded.length > MAX_REQUEST_BYTES) {
      throw new DietCodeBridgeError('invalid_params', `request exceeds ${MAX_REQUEST_BYTES} bytes`);
    }

    const timeoutMs = options.timeoutMs ?? this.config.requestTimeoutMs;
    const started = performance.now();

    await new Promise<void>((resolve, reject) => {
      socket.write(encoded, (err) => {
        if (err) {
          reject(new DietCodeBridgeError('transport_error', err.message));
          return;
        }
        resolve();
      });
    });

    while (true) {
      const frame = await this.readJsonFrame(method, timeoutMs - (performance.now() - started));
      const frameId = frame.id;
      if (frameId === requestId) {
        frame._clientDurationMs = Math.round(performance.now() - started);
        return frame;
      }
      if (frameId == null && typeof (frame as { method?: string }).method === 'string') {
        continue;
      }
      throw new DietCodeBridgeError(
        'transport_error',
        `received response id ${String(frameId)} while waiting for ${requestId}`,
      );
    }
  }

  private async readJsonFrame(method: string, remainingMs: number): Promise<RpcEnvelope> {
    if (remainingMs <= 0) {
      throw new DietCodeBridgeError('nested_call_timeout', `RPC timed out waiting for ${method}`);
    }

    const deadline = Date.now() + remainingMs;
    while (Date.now() <= deadline) {
      const newlineIndex = this.buffer.indexOf(0x0a);
      if (newlineIndex >= 0) {
        const line = this.buffer.subarray(0, newlineIndex);
        this.buffer = this.buffer.subarray(newlineIndex + 1);
        if (line.length === 0) {
          continue;
        }
        if (line.length > MAX_RESPONSE_BYTES) {
          throw new DietCodeBridgeError(
            'transport_error',
            `response exceeds maximum allowed size of ${MAX_RESPONSE_BYTES} bytes`,
          );
        }
        try {
          const frame = JSON.parse(line.toString('utf8')) as RpcEnvelope;
          if (typeof frame !== 'object' || frame === null) {
            throw new DietCodeBridgeError('transport_error', `non-object JSON frame for ${method}`);
          }
          return frame;
        } catch (error) {
          if (error instanceof DietCodeBridgeError) {
            throw error;
          }
          throw new DietCodeBridgeError(
            'transport_error',
            `invalid JSON frame while waiting for ${method}: ${String(error)}`,
          );
        }
      }

      const chunk = await this.readSocketChunk(Math.min(250, deadline - Date.now()));
      if (chunk.length === 0) {
        if (this.closed || !this.socket || this.socket.destroyed) {
          throw new DietCodeBridgeError('transport_error', `socket closed while waiting for ${method}`);
        }
        continue;
      }
      this.buffer = Buffer.concat([this.buffer, chunk]);
      if (this.buffer.length > MAX_RESPONSE_BYTES + 1 && this.buffer.indexOf(0x0a) < 0) {
        throw new DietCodeBridgeError(
          'transport_error',
          `response exceeds maximum allowed size of ${MAX_RESPONSE_BYTES} bytes`,
        );
      }
    }

    throw new DietCodeBridgeError('nested_call_timeout', `RPC timed out waiting for ${method}`);
  }

  private readSocketChunk(waitMs: number): Promise<Buffer> {
    const socket = this.socket;
    if (!socket) {
      return Promise.reject(new DietCodeBridgeError('transport_error', 'socket not connected'));
    }

    return new Promise((resolve, reject) => {
      const onData = (chunk: Buffer) => {
        cleanup();
        resolve(chunk);
      };
      const onError = (err: Error) => {
        cleanup();
        reject(new DietCodeBridgeError('transport_error', err.message));
      };
      const onClose = () => {
        cleanup();
        resolve(Buffer.alloc(0));
      };
      const timer = setTimeout(() => {
        cleanup();
        resolve(Buffer.alloc(0));
      }, Math.max(0, waitMs));

      const cleanup = () => {
        clearTimeout(timer);
        socket.off('data', onData);
        socket.off('error', onError);
        socket.off('close', onClose);
      };

      socket.on('data', onData);
      socket.once('error', onError);
      socket.once('close', onClose);
    });
  }

  private async ensureSocket(appPath?: string): Promise<void> {
    if (await this.socketProbe()) {
      return;
    }

    const binary = appPath ?? this.config.appPath;
    if (!binary) {
      throw new DietCodeBridgeError(
        'runtime_unavailable',
        `control socket not available at ${this.config.socketPath}`,
      );
    }

    await new Promise<void>((resolve, reject) => {
      const child = spawn(binary, ['--ensure-socket'], {
        stdio: 'ignore',
        env: process.env,
      });
      child.on('error', reject);
      child.on('exit', (code) => {
        if (code === 0) {
          resolve();
        } else {
          reject(new DietCodeBridgeError('runtime_unavailable', `--ensure-socket exited ${code}`));
        }
      });
    });

    const deadline = Date.now() + this.config.connectTimeoutMs;
    while (Date.now() < deadline) {
      if (await this.socketProbe()) {
        return;
      }
      await sleep(200);
    }

    throw new DietCodeBridgeError(
      'runtime_unavailable',
      `socket not ready at ${this.config.socketPath}`,
    );
  }

  private socketProbe(): Promise<boolean> {
    return new Promise((resolve) => {
      const probe = net.createConnection(this.config.socketPath);
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

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export { isBridgeError };

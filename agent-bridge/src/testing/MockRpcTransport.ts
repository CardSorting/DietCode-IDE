import type { RpcCaller } from '../client/RpcTransport.js';
import type { RpcEnvelope } from '../contracts/types.js';

/** Test-only in-memory RPC transport. Not for production agent use. */
export class MockRpcTransport implements RpcCaller {
  private readonly handlers: Map<string, (params: Record<string, unknown>) => RpcEnvelope | Promise<RpcEnvelope>>;
  public calls: Array<{ method: string; params: Record<string, unknown> }> = [];

  constructor(
    handlers: Record<
      string,
      (params: Record<string, unknown>) => RpcEnvelope | Promise<RpcEnvelope>
    > = {},
  ) {
    this.handlers = new Map(Object.entries(handlers));
  }

  async connect(): Promise<void> {
    return;
  }

  async close(): Promise<void> {
    return;
  }

  async call(
    method: string,
    params: Record<string, unknown> = {},
  ): Promise<RpcEnvelope> {
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

  setHandler(
    method: string,
    handler: (params: Record<string, unknown>) => RpcEnvelope | Promise<RpcEnvelope>,
  ): void {
    this.handlers.set(method, handler);
  }
}

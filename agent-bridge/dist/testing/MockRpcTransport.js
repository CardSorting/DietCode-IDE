/** Test-only in-memory RPC transport. Not for production agent use. */
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
//# sourceMappingURL=MockRpcTransport.js.map
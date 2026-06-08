import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readFile } from 'node:fs/promises';
import net from 'node:net';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

const PORT = Number(process.env.COCKPIT_BRIDGE_PORT ?? 9477);
const SOCKET_PATH = process.env.DIETCODE_SOCKET_PATH ?? join(homedir(), '.dietcode', 'control.sock');
const TOKEN_PATH = process.env.DIETCODE_TOKEN_PATH ?? join(homedir(), '.dietcode', 'session.token');

interface RpcRequest {
  jsonrpc: string;
  id: string;
  method: string;
  params?: Record<string, unknown>;
}

interface KernelEvent {
  id: string;
  sequence: number;
  timestamp: string;
  type: string;
  source: string;
  detail: string;
  payload?: Record<string, unknown>;
}

const sseClients = new Set<ServerResponse>();
let lastEventSequence = 0;
let pollTimer: NodeJS.Timeout | null = null;

async function readToken(): Promise<string> {
  return readFile(TOKEN_PATH, 'utf8').then((t) => t.trim());
}

async function rpcCall(method: string, params: Record<string, unknown> = {}): Promise<unknown> {
  const token = await readToken();
  const request: RpcRequest = {
    jsonrpc: '2.0',
    id: randomUUID(),
    method,
    params: { ...params, token },
  };
  const payload = JSON.stringify(request) + '\n';

  return new Promise((resolve, reject) => {
    const socket = net.createConnection(SOCKET_PATH);
    let buffer = '';

    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error(`RPC timeout: ${method}`));
    }, 30_000);

    socket.on('data', (chunk) => {
      buffer += chunk.toString('utf8');
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const envelope = JSON.parse(line) as { result?: unknown; error?: { message: string } };
          clearTimeout(timer);
          socket.end();
          if (envelope.error) {
            reject(new Error(envelope.error.message));
            return;
          }
          resolve(envelope.result);
          return;
        } catch {
          // keep buffering
        }
      }
    });

    socket.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });

    socket.write(payload);
  });
}

function broadcastEvent(event: KernelEvent): void {
  const frame = `data: ${JSON.stringify(event)}\n\n`;
  for (const client of sseClients) {
    client.write(frame);
  }
}

async function pollKernelEvents(): Promise<void> {
  try {
    const result = (await rpcCall('events.recent', {
      afterSequence: lastEventSequence,
      limit: 100,
    })) as { events?: KernelEvent[] };
    const events = result.events ?? [];
    for (const event of events) {
      if (event.sequence > lastEventSequence) {
        lastEventSequence = event.sequence;
        broadcastEvent(event);
      }
    }
  } catch {
    // kernel may not be running yet
  }
}

function startEventPolling(): void {
  if (pollTimer) return;
  pollTimer = setInterval(() => {
    void pollKernelEvents();
  }, 500);
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk.toString('utf8');
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

function setCors(res: ServerResponse): void {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

const server = createServer(async (req, res) => {
  setCors(res);

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.url === '/events' && req.method === 'GET') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    });
    res.write(': connected\n\n');
    sseClients.add(res);
    req.on('close', () => sseClients.delete(res));
    void pollKernelEvents();
    return;
  }

  if (req.url === '/api/status' && req.method === 'GET') {
    try {
      const ping = (await rpcCall('rpc.ping')) as Record<string, unknown>;
      const root = (await rpcCall('workspace.getRoot')) as Record<string, unknown>;
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ connected: true, ping, workspace: root }));
    } catch (err) {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ connected: false, error: String(err) }));
    }
    return;
  }

  if (req.url === '/api/rpc' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const parsed = JSON.parse(body) as { method: string; params?: Record<string, unknown> };
      const result = await rpcCall(parsed.method, parsed.params ?? {});
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ result }));
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: String(err) }));
    }
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not_found' }));
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`DietCode cockpit bridge listening on http://127.0.0.1:${PORT}`);
  console.log(`Kernel socket: ${SOCKET_PATH}`);
  startEventPolling();
});

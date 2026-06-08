import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readFile } from 'node:fs/promises';
import net from 'node:net';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';

import {
  broadcastEvent,
  emitBridgeEvent,
  getLastKernelEventSequence,
  normalizeKernelEvent,
  registerSseClient,
  setLastKernelEventSequence,
  unregisterSseClient,
} from './events.js';
import { clearAllTasks, createTask, getTask, listTasks } from './taskRegistry.js';
import {
  cancelTask,
  clearTaskAwaitingApproval,
  retryTask,
  setTaskAwaitingApproval,
  startGovernedTask,
} from './taskRunner.js';
import {
  bootstrapSessionRecovery,
  getSessionState,
  syncPendingApprovalsFromKernel,
} from './sessionRecovery.js';
import { clearSessionFiles, exportSessionBundle } from './sessionStore.js';
import {
  buildHealthSnapshot,
  dismissBridgeRecovered,
  probeKernel,
  refreshExpiredApprovals,
  setSessionAnchorWorkspace,
} from './healthMonitor.js';

const PORT = Number(process.env.COCKPIT_BRIDGE_PORT ?? 9477);
const SOCKET_PATH = process.env.DIETCODE_SOCKET_PATH ?? join(homedir(), '.dietcode', 'control.sock');
const TOKEN_PATH = process.env.DIETCODE_TOKEN_PATH ?? join(homedir(), '.dietcode', 'session.token');

interface RpcRequest {
  jsonrpc: string;
  id: string;
  method: string;
  params?: Record<string, unknown>;
}

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

async function pollKernelEvents(): Promise<void> {
  try {
    await probeKernel(rpcCall);
    const result = (await rpcCall('events.recent', {
      afterSequence: getLastKernelEventSequence(),
      limit: 100,
    })) as { events?: Record<string, unknown>[] };
    const events = result.events ?? [];
    for (const raw of events) {
      const sequence = Number(raw.sequence ?? 0);
      if (sequence <= getLastKernelEventSequence()) continue;
      setLastKernelEventSequence(sequence);
      const event = normalizeKernelEvent(raw);

      if (event.type === 'verify.complete' || event.type.startsWith('verify.')) {
        broadcastEvent({
          ...event,
          type: event.type === 'verify.complete' ? 'verify.completed' : event.type,
        });
      } else if (event.type === 'approval.required') {
        broadcastEvent(event);
        const approvalId =
          typeof event.payload?.approvalId === 'string'
            ? event.payload.approvalId
            : typeof (event.payload?.approval as Record<string, unknown> | undefined)?.approvalId ===
                'string'
              ? ((event.payload?.approval as Record<string, unknown>).approvalId as string)
              : undefined;
        if (event.taskId) {
          setTaskAwaitingApproval(event.taskId, approvalId);
        }
        void syncPendingApprovalsFromKernel(rpcCall);
      } else if (event.type === 'approval.resolved') {
        broadcastEvent(event);
        if (event.taskId) {
          clearTaskAwaitingApproval(event.taskId);
        }
        void syncPendingApprovalsFromKernel(rpcCall);
        void refreshExpiredApprovals(rpcCall);
      } else {
        broadcastEvent(event);
      }
    }
  } catch {
    // kernel offline — health snapshot reflects it
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
    registerSseClient(res);
    req.on('close', () => unregisterSseClient(res));
    void pollKernelEvents();
    return;
  }

  if (req.url === '/api/health' && req.method === 'GET') {
    await probeKernel(rpcCall);
    await refreshExpiredApprovals(rpcCall);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(buildHealthSnapshot(listTasks())));
    return;
  }

  if (req.url === '/api/session' && req.method === 'GET') {
    const state = getSessionState();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        ...state,
        health: buildHealthSnapshot(listTasks()),
      }),
    );
    return;
  }

  if (req.url === '/api/session/clear' && req.method === 'POST') {
    try {
      clearAllTasks();
      await clearSessionFiles();
      dismissBridgeRecovered();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, mode: 'session_cleared' }));
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: String(err) }));
    }
    return;
  }

  if (req.url === '/api/session/export' && req.method === 'POST') {
    try {
      const path = await exportSessionBundle(listTasks());
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, path, mode: 'session_export' }));
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: String(err) }));
    }
    return;
  }

  if (req.url === '/api/status' && req.method === 'GET') {
    try {
      await probeKernel(rpcCall);
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

  if (req.url === '/api/reconnect' && req.method === 'POST') {
    try {
      await probeKernel(rpcCall);
      await syncPendingApprovalsFromKernel(rpcCall);
      await refreshExpiredApprovals(rpcCall);
      await pollKernelEvents();
      dismissBridgeRecovered();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, health: buildHealthSnapshot(listTasks()) }));
    } catch (err) {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: String(err) }));
    }
    return;
  }

  if (req.url === '/api/tasks' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ tasks: listTasks() }));
    return;
  }

  const taskActionMatch = req.url?.match(/^\/api\/tasks\/([^/]+)\/(retry|cancel)$/);
  if (taskActionMatch && req.method === 'POST') {
    const taskId = taskActionMatch[1];
    const action = taskActionMatch[2];
    if (action === 'retry') {
      const task = retryTask(taskId);
      if (!task) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'retry_not_allowed' }));
        return;
      }
      setSessionAnchorWorkspace(task.workspace);
      res.writeHead(202, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ task, mode: 'task_retry' }));
      return;
    }
    if (action === 'cancel') {
      const task = cancelTask(taskId);
      if (!task) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'cancel_not_allowed' }));
        return;
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ task, mode: 'task_cancelled' }));
      return;
    }
  }

  const taskMatch = req.url?.match(/^\/api\/tasks\/([^/?]+)$/);
  if (taskMatch && req.method === 'GET') {
    const task = getTask(taskMatch[1]);
    if (!task) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'not_found' }));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ task }));
    return;
  }

  if (req.url === '/api/tasks' && req.method === 'POST') {
    try {
      const body = await readBody(req);
      const parsed = JSON.parse(body || '{}') as {
        message?: string;
        workspace?: string;
        mode?: 'supervised' | 'trusted';
      };
      if (!parsed.message?.trim()) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'message required' }));
        return;
      }

      let workspace = parsed.workspace?.trim();
      if (!workspace) {
        try {
          const root = (await rpcCall('workspace.getRoot')) as { path?: string };
          workspace = root.path;
        } catch {
          workspace = undefined;
        }
      }
      if (!workspace) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'workspace required' }));
        return;
      }

      const mode = parsed.mode === 'trusted' ? 'trusted' : 'supervised';
      const task = createTask({
        message: parsed.message.trim(),
        workspace,
        mode,
      });

      setSessionAnchorWorkspace(workspace);
      startGovernedTask(task);

      res.writeHead(202, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ task, mode: 'governed_task_accepted' }));
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: String(err) }));
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

  if (req.url === '/api/approvals/refresh' && req.method === 'POST') {
    try {
      await syncPendingApprovalsFromKernel(rpcCall);
      await refreshExpiredApprovals(rpcCall);
      const pending = (await rpcCall('approval.list', { status: 'pending', limit: 50 })) as Record<
        string,
        unknown
      >;
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, pending, health: buildHealthSnapshot(listTasks()) }));
    } catch (err) {
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: String(err) }));
    }
    return;
  }

  const approvalsMatch = req.url?.match(/^\/api\/approvals(?:\/([^/?]+)(?:\/resolve)?)?(?:\?(.*))?$/);
  if (approvalsMatch) {
    const approvalId = approvalsMatch[1];
    const isResolve = req.url?.endsWith('/resolve');
    const query = new URLSearchParams(approvalsMatch[2] ?? '');

    if (!approvalId && req.method === 'GET') {
      try {
        const status = query.get('status') ?? undefined;
        const limit = query.get('limit') ? Number(query.get('limit')) : undefined;
        const result = (await rpcCall('approval.list', {
          ...(status ? { status } : {}),
          ...(limit ? { limit } : {}),
        })) as Record<string, unknown>;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: String(err) }));
      }
      return;
    }

    if (approvalId && !isResolve && req.method === 'GET') {
      try {
        const result = (await rpcCall('approval.get', { approvalId })) as Record<string, unknown>;
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: String(err) }));
      }
      return;
    }

    if (approvalId && isResolve && req.method === 'POST') {
      try {
        const body = await readBody(req);
        const parsed = JSON.parse(body || '{}') as {
          decision?: string;
          reason?: string;
          resolvedBy?: string;
        };
        const result = (await rpcCall('approval.resolve', {
          approvalId,
          decision: parsed.decision,
          reason: parsed.reason,
          resolvedBy: parsed.resolvedBy ?? 'cockpit',
        })) as Record<string, unknown>;
        await syncPendingApprovalsFromKernel(rpcCall);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: String(err) }));
      }
      return;
    }
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not_found' }));
});

async function main(): Promise<void> {
  await bootstrapSessionRecovery(rpcCall);
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`DietCode cockpit bridge listening on http://127.0.0.1:${PORT}`);
    console.log(`Kernel socket: ${SOCKET_PATH}`);
    startEventPolling();
  });
}

void main();

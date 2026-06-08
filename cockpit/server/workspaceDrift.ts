export interface AffectedFile {
  path: string;
  reason: string;
  source?: string;
}

export interface WorkspaceStatus {
  root?: string;
  gitHead?: string;
  gitBranch?: string;
  anchorGitHead?: string;
  anchorRefreshedAt?: string;
  contextRefreshId?: number;
  dirtyFiles?: string[];
  affectedFiles?: AffectedFile[];
  driftDetected?: boolean;
  externalChangeDetected?: boolean;
  requiresContextRefresh?: boolean;
  lastVerifiedCommand?: string;
  lastVerifiedAt?: string;
  lastVerifyPassed?: boolean;
  refreshed?: boolean;
}

let cachedStatus: WorkspaceStatus | null = null;
let cachedAt: string | undefined;

export function getCachedWorkspaceStatus(): WorkspaceStatus | null {
  return cachedStatus;
}

export function setCachedWorkspaceStatus(status: WorkspaceStatus): void {
  cachedStatus = status;
  cachedAt = new Date().toISOString();
}

export async function fetchWorkspaceStatus(
  rpcCall: (method: string, params?: Record<string, unknown>) => Promise<unknown>,
): Promise<WorkspaceStatus> {
  const status = (await rpcCall('workspace.status')) as WorkspaceStatus;
  setCachedWorkspaceStatus(status);
  return status;
}

export async function refreshWorkspaceAnchor(
  rpcCall: (method: string, params?: Record<string, unknown>) => Promise<unknown>,
): Promise<WorkspaceStatus> {
  const status = (await rpcCall('workspace.refreshAnchor')) as WorkspaceStatus;
  setCachedWorkspaceStatus(status);
  return status;
}

export async function continueWorkspaceAnyway(
  rpcCall: (method: string, params?: Record<string, unknown>) => Promise<unknown>,
): Promise<WorkspaceStatus> {
  await rpcCall('workspace.continueAnyway');
  const status = await fetchWorkspaceStatus(rpcCall);
  return { ...status, continueAnyway: true } as WorkspaceStatus & { continueAnyway?: boolean };
}

export async function rerunLastVerify(
  rpcCall: (method: string, params?: Record<string, unknown>) => Promise<unknown>,
): Promise<Record<string, unknown>> {
  const status = cachedStatus ?? (await fetchWorkspaceStatus(rpcCall));
  const command = status.lastVerifiedCommand?.trim();
  if (!command) {
    throw new Error('no_last_verify_command');
  }
  const result = (await rpcCall('verify.run', { command })) as Record<string, unknown>;
  await fetchWorkspaceStatus(rpcCall);
  return result;
}

export function formatAffectedFileLine(file: AffectedFile): string {
  return `${file.path} — ${file.reason}`;
}

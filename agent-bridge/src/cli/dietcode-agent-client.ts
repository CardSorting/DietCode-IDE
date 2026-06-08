#!/usr/bin/env node
import { readFile } from 'node:fs/promises';

import { DietCodeBridgeClient } from '../client/DietCodeBridgeClient.js';
import { resolveAppPath } from '../client/config.js';
import { isBridgeError } from '../contracts/BridgeError.js';
import type { PatchBatchEntry } from '../contracts/types.js';

interface CliOptions {
  pretty: boolean;
  compact: boolean;
  errorJson: boolean;
  noStart: boolean;
  waitReady: boolean;
  socketPath?: string;
  tokenPath?: string;
  appPath?: string;
  workspaceRoot?: string;
}

function parseFlags(argv: string[]): { flags: CliOptions; args: string[] } {
  const flags: CliOptions = {
    pretty: false,
    compact: false,
    errorJson: true,
    noStart: false,
    waitReady: false,
  };
  const args: string[] = [];

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--pretty') {
      flags.pretty = true;
    } else if (arg === '--compact' || arg === '--json') {
      flags.compact = true;
    } else if (arg === '--error-json') {
      flags.errorJson = true;
    } else if (arg === '--no-start') {
      flags.noStart = true;
    } else if (arg === '--wait-ready') {
      flags.waitReady = true;
    } else if (arg === '--socket' && argv[i + 1]) {
      flags.socketPath = argv[++i];
    } else if (arg === '--token' && argv[i + 1]) {
      flags.tokenPath = argv[++i];
    } else if (arg === '--app' && argv[i + 1]) {
      flags.appPath = argv[++i];
    } else if (arg === '--workspace' && argv[i + 1]) {
      flags.workspaceRoot = argv[++i];
    } else {
      args.push(arg);
    }
  }

  return { flags, args };
}

function emit(value: unknown, pretty: boolean, compact: boolean): void {
  const text =
    pretty && !compact ? JSON.stringify(value, null, 2) : JSON.stringify(value);
  process.stdout.write(`${text}\n`);
}

function emitError(value: unknown, flags: CliOptions): void {
  const text = flags.pretty && !flags.compact ? JSON.stringify(value, null, 2) : JSON.stringify(value);
  process.stderr.write(`${text}\n`);
}

function usage(): void {
  process.stderr.write(`dietcode-agent-client — DietCode Agent Bridge CLI

Commands:
  profile
  diagnostics
  search literal <query>
  search tokens <token...>
  search paths <query>
  stat <path>
  patch safe-file <path> <diff-file>
  patch safe-batch <patch-json>
  timeline recent
  activity recent
  verify fast

Options:
  --pretty         Pretty-print JSON
  --compact        Compact JSON (default)
  --error-json     Print failures as JSON on stderr (default)
  --wait-ready     Wait for RPC readiness during connect
  --no-start       Do not auto-start DietCode socket
  --socket PATH    Control socket path
  --token PATH     Session token path
  --app PATH       DietCode binary for --ensure-socket
  --workspace PATH Workspace root to open when none is active
`);
}

async function main(): Promise<number> {
  const { flags, args } = parseFlags(process.argv.slice(2));

  if (args.length === 0 && !flags.waitReady) {
    usage();
    return 1;
  }

  const appPath = flags.appPath ?? resolveAppPath();
  const client = new DietCodeBridgeClient({
    socketPath: flags.socketPath,
    tokenPath: flags.tokenPath,
    startApp: !flags.noStart,
    appPath,
    workspaceRoot: flags.workspaceRoot,
  });

  try {
    if (flags.waitReady && args.length === 0) {
      await client.connect({ startApp: !flags.noStart, appPath, workspaceRoot: flags.workspaceRoot });
      emit({ ok: true, rpcReady: true, profile: client.getRuntimeProfile() }, flags.pretty, flags.compact);
      return 0;
    }

    await client.connect({ startApp: !flags.noStart, appPath, workspaceRoot: flags.workspaceRoot });

    const [command, subcommand, ...rest] = args;
    let result: unknown;

    switch (command) {
      case 'profile':
        result = client.getRuntimeProfile();
        break;
      case 'diagnostics':
        result = await client.getDiagnostics();
        break;
      case 'search': {
        if (subcommand === 'literal' && rest[0]) {
          result = await client.searchLiteral(rest.join(' '));
        } else if (subcommand === 'tokens' && rest.length > 0) {
          result = await client.searchTokens(rest);
        } else if (subcommand === 'paths' && rest[0]) {
          result = await client.searchPaths(rest.join(' '));
        } else {
          usage();
          return 1;
        }
        break;
      }
      case 'stat':
        if (!subcommand) {
          usage();
          return 1;
        }
        result = await client.getFileStat(subcommand);
        break;
      case 'patch': {
        if (subcommand === 'safe-file' && rest[0] && rest[1]) {
          const diff = await readFile(rest[1], 'utf8');
          result = await client.safePatchFile(rest[0], diff);
        } else if (subcommand === 'safe-batch' && rest[0]) {
          const parsed = JSON.parse(rest[0]) as PatchBatchEntry[];
          result = await client.safePatchBatch(parsed);
        } else {
          usage();
          return 1;
        }
        break;
      }
      case 'timeline':
        if (subcommand === 'recent') {
          result = await client.getTimeline();
        } else {
          usage();
          return 1;
        }
        break;
      case 'activity':
        if (subcommand === 'recent') {
          result = await client.getRecentActivity();
        } else {
          usage();
          return 1;
        }
        break;
      case 'verify':
        if (subcommand === 'fast') {
          result = await client.verifyFast();
        } else {
          usage();
          return 1;
        }
        break;
      default:
        usage();
        return 1;
    }

    emit(result, flags.pretty, flags.compact);
    return 0;
  } catch (error) {
    const payload = isBridgeError(error)
      ? { ok: false, error: error.toJSON() }
      : { ok: false, error: { code: 'unknown', message: String(error) } };
    if (flags.errorJson) {
      emitError(payload, flags);
    } else {
      emitError(payload.error, flags);
    }
    return 1;
  } finally {
    await client.close();
  }
}

main().then((code) => process.exit(code));

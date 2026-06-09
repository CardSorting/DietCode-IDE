#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { DietCodeBridgeClient } from '../client/DietCodeBridgeClient.js';
import { resolveAppPath } from '../client/config.js';
import { isBridgeError } from '../contracts/BridgeError.js';
import { buildLineReplacementPatchFromContent } from '../utils/unifiedDiff.js';
function parseFlags(argv) {
    const flags = {
        pretty: false,
        compact: false,
        errorJson: true,
        noStart: false,
        waitReady: false,
    };
    const args = [];
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--pretty') {
            flags.pretty = true;
        }
        else if (arg === '--compact' || arg === '--json') {
            flags.compact = true;
        }
        else if (arg === '--error-json') {
            flags.errorJson = true;
        }
        else if (arg === '--no-start') {
            flags.noStart = true;
        }
        else if (arg === '--wait-ready') {
            flags.waitReady = true;
        }
        else if (arg === '--socket' && argv[i + 1]) {
            flags.socketPath = argv[++i];
        }
        else if (arg === '--token' && argv[i + 1]) {
            flags.tokenPath = argv[++i];
        }
        else if (arg === '--app' && argv[i + 1]) {
            flags.appPath = argv[++i];
        }
        else if (arg === '--workspace' && argv[i + 1]) {
            flags.workspaceRoot = argv[++i];
        }
        else if (arg === '--max-results' && argv[i + 1]) {
            flags.maxResults = Number(argv[++i]);
        }
        else if (arg === '--idempotency-key' && argv[i + 1]) {
            flags.idempotencyKey = argv[++i];
        }
        else if (arg === '--task-id' && argv[i + 1]) {
            flags.taskId = argv[++i];
        }
        else if (arg === '--coherence-retry') {
            flags.coherenceRetry = true;
        }
        else if (arg === '--line-search' && argv[i + 1]) {
            flags.lineSearch = argv[++i];
        }
        else if (arg === '--line-replace' && argv[i + 1]) {
            flags.lineReplace = argv[++i];
        }
        else {
            args.push(arg);
        }
    }
    return { flags, args };
}
function emit(value, pretty, compact) {
    const text = pretty && !compact ? JSON.stringify(value, null, 2) : JSON.stringify(value);
    process.stdout.write(`${text}\n`);
}
function emitError(value, flags) {
    const text = flags.pretty && !flags.compact ? JSON.stringify(value, null, 2) : JSON.stringify(value);
    process.stderr.write(`${text}\n`);
}
function usage() {
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
  operation status <idempotencyKey>
  timeline recent [--limit N] [--since-revision N]
  activity recent [--limit N]
  verify fast
  shell pwd
  shell cd <path>
  shell rg <pattern> [--path PATH]
  shell head <path> [--lines N]
  shell tail <path> [--lines N]
  shell sed <path> <startLine> <endLine>
  shell cat-small <path>

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
  --max-results N  Cap search result count
  --idempotency-key KEY  Replay-safe key for patch commands
  --task-id ID           Governed task id (defaults to DIETCODE_TASK_ID)
  --coherence-retry      Enable one automatic coherence recovery retry (safe-file)
  --line-search TEXT     With --coherence-retry: line to find in file
  --line-replace TEXT    With --coherence-retry: replacement line
`);
}
async function main() {
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
        let result;
        const searchOptions = flags.maxResults && flags.maxResults > 0 ? { maxResults: flags.maxResults } : undefined;
        const patchOptions = {
            ...(flags.idempotencyKey ? { idempotencyKey: flags.idempotencyKey } : {}),
            ...(flags.taskId || process.env.DIETCODE_TASK_ID
                ? { taskId: flags.taskId ?? process.env.DIETCODE_TASK_ID?.trim() }
                : {}),
        };
        if (flags.coherenceRetry && flags.lineSearch && flags.lineReplace) {
            patchOptions.lineReplacement = {
                search: flags.lineSearch,
                replace: flags.lineReplace,
            };
        }
        else if (flags.coherenceRetry && flags.lineSearch) {
            const search = flags.lineSearch;
            const replace = flags.lineReplace ?? flags.lineSearch;
            patchOptions.buildPatchFromContent = ({ path, content }) => buildLineReplacementPatchFromContent(path, content, search, replace);
        }
        switch (command) {
            case 'profile':
                result = client.getRuntimeProfile();
                break;
            case 'diagnostics':
                result = await client.getDiagnostics();
                break;
            case 'search': {
                if (subcommand === 'literal' && rest[0]) {
                    result = await client.searchLiteral(rest.join(' '), searchOptions);
                }
                else if (subcommand === 'tokens' && rest.length > 0) {
                    result = await client.searchTokens(rest, searchOptions);
                }
                else if (subcommand === 'paths' && rest[0]) {
                    result = await client.searchPaths(rest.join(' '), searchOptions);
                }
                else {
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
                    result = await client.safePatchFile(rest[0], diff, patchOptions);
                }
                else if (subcommand === 'safe-batch' && rest[0]) {
                    const parsed = JSON.parse(rest[0]);
                    result = await client.safePatchBatch(parsed, patchOptions);
                }
                else {
                    usage();
                    return 1;
                }
                break;
            }
            case 'operation':
                if (subcommand === 'status' && rest[0]) {
                    result = await client.getOperationStatus(rest[0]);
                }
                else {
                    usage();
                    return 1;
                }
                break;
            case 'timeline':
                if (subcommand === 'recent') {
                    const limitIdx = rest.indexOf('--limit');
                    const sinceIdx = rest.indexOf('--since-revision');
                    const limit = limitIdx >= 0 ? Number(rest[limitIdx + 1]) : undefined;
                    const sinceRevision = sinceIdx >= 0 ? Number(rest[sinceIdx + 1]) : undefined;
                    result = await client.getTimeline({
                        ...(limit && limit > 0 ? { limit } : {}),
                        ...(sinceRevision && sinceRevision > 0 ? { sinceRevision } : {}),
                    });
                }
                else {
                    usage();
                    return 1;
                }
                break;
            case 'activity':
                if (subcommand === 'recent') {
                    const limitIdx = rest.indexOf('--limit');
                    const limit = limitIdx >= 0 ? Number(rest[limitIdx + 1]) : undefined;
                    result = await client.getRecentActivity(limit && limit > 0 ? { limit } : {});
                }
                else {
                    usage();
                    return 1;
                }
                break;
            case 'verify':
                if (subcommand === 'fast') {
                    result = await client.verifyFast();
                }
                else {
                    usage();
                    return 1;
                }
                break;
            case 'shell': {
                if (subcommand === 'pwd') {
                    result = await client.shellPwd();
                }
                else if (subcommand === 'cd' && rest[0]) {
                    result = await client.shellCd(rest[0]);
                }
                else if (subcommand === 'rg' && rest[0]) {
                    const pathIdx = rest.indexOf('--path');
                    const path = pathIdx >= 0 ? rest[pathIdx + 1] : undefined;
                    const pattern = rest[0];
                    result = await client.shellRg(pattern, path ? { path } : {});
                }
                else if (subcommand === 'head' && rest[0]) {
                    const linesIdx = rest.indexOf('--lines');
                    const lines = linesIdx >= 0 ? Number(rest[linesIdx + 1]) : undefined;
                    result = await client.shellHead(rest[0], lines);
                }
                else if (subcommand === 'tail' && rest[0]) {
                    const linesIdx = rest.indexOf('--lines');
                    const lines = linesIdx >= 0 ? Number(rest[linesIdx + 1]) : undefined;
                    result = await client.shellTail(rest[0], lines);
                }
                else if (subcommand === 'sed' && rest[0] && rest[1] && rest[2]) {
                    result = await client.shellSedRange(rest[0], Number(rest[1]), Number(rest[2]));
                }
                else if (subcommand === 'cat-small' && rest[0]) {
                    result = await client.shellCatSmall(rest[0]);
                }
                else {
                    usage();
                    return 1;
                }
                break;
            }
            default:
                usage();
                return 1;
        }
        if (command === 'shell' &&
            result &&
            typeof result === 'object' &&
            result.partial === true) {
            const envelope = result;
            const hint = envelope.recoveryHint ?? envelope.warnings?.join(', ') ?? 'partial shell result';
            process.stderr.write(`warning: ${hint}\n`);
        }
        emit(result, flags.pretty, flags.compact);
        return 0;
    }
    catch (error) {
        const payload = isBridgeError(error)
            ? { ok: false, error: error.toJSON() }
            : { ok: false, error: { code: 'unknown', message: String(error) } };
        if (flags.errorJson) {
            emitError(payload, flags);
        }
        else {
            emitError(payload.error, flags);
        }
        return 1;
    }
    finally {
        await client.close();
    }
}
main().then((code) => process.exit(code));
//# sourceMappingURL=dietcode-agent-client.js.map
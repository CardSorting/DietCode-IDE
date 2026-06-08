#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { DietCodeBridgeClient } from '../client/DietCodeBridgeClient.js';
import { isBridgeError } from '../client/RpcTransport.js';
function parseFlags(argv) {
    const flags = { pretty: false, noStart: false };
    const args = [];
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--pretty') {
            flags.pretty = true;
        }
        else if (arg === '--no-start') {
            flags.noStart = true;
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
        else {
            args.push(arg);
        }
    }
    return { flags, args };
}
function emit(value, pretty) {
    const text = pretty ? JSON.stringify(value, null, 2) : JSON.stringify(value);
    process.stdout.write(`${text}\n`);
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
  timeline recent
  activity recent
  verify fast

Options:
  --pretty       Pretty-print JSON
  --no-start     Do not auto-start DietCode socket
  --socket PATH  Control socket path
  --token PATH   Session token path
  --app PATH     DietCode binary for --ensure-socket
`);
}
async function main() {
    const { flags, args } = parseFlags(process.argv.slice(2));
    if (args.length === 0) {
        usage();
        return 1;
    }
    const client = new DietCodeBridgeClient({
        socketPath: flags.socketPath,
        tokenPath: flags.tokenPath,
        startApp: !flags.noStart,
        appPath: flags.appPath,
    });
    try {
        await client.connect({ startApp: !flags.noStart, appPath: flags.appPath });
        const [command, subcommand, ...rest] = args;
        let result;
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
                }
                else if (subcommand === 'tokens' && rest.length > 0) {
                    result = await client.searchTokens(rest);
                }
                else if (subcommand === 'paths' && rest[0]) {
                    result = await client.searchPaths(rest.join(' '));
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
                    result = await client.safePatchFile(rest[0], diff);
                }
                else if (subcommand === 'safe-batch' && rest[0]) {
                    const parsed = JSON.parse(rest[0]);
                    result = await client.safePatchBatch(parsed);
                }
                else {
                    usage();
                    return 1;
                }
                break;
            }
            case 'timeline':
                if (subcommand === 'recent') {
                    result = await client.getTimeline();
                }
                else {
                    usage();
                    return 1;
                }
                break;
            case 'activity':
                if (subcommand === 'recent') {
                    result = await client.getRecentActivity();
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
            default:
                usage();
                return 1;
        }
        emit(result, flags.pretty);
        return 0;
    }
    catch (error) {
        const payload = isBridgeError(error)
            ? { ok: false, error }
            : { ok: false, error: { code: 'unknown', message: String(error) } };
        process.stderr.write(`${JSON.stringify(payload)}\n`);
        return 1;
    }
    finally {
        await client.close();
    }
}
main().then((code) => process.exit(code));
//# sourceMappingURL=dietcode-agent-client.js.map
/**
 * Discovers model IDs from VibeProxy/claude-code-proxy for Happy's mobile picker.
 *
 * The proxy intentionally owns its model registry, so Happy should not duplicate
 * that registry. The command output is grouped by provider, and providers with a
 * working authentication status are advertised to the client. An explicit
 * provider list can be supplied for proxies whose auth status is unavailable.
 */

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import os from 'node:os';
import { basename, join } from 'node:path';
import { existsSync } from 'node:fs';

const execFileAsync = promisify(execFile);
const DEFAULT_PROXY_BINARIES = ['vibeproxy', 'claude-code-proxy'] as const;
const COMMAND_TIMEOUT_MS = 5_000;
const COMMAND_MAX_BUFFER = 2 * 1024 * 1024;

export type VibeProxyModelOption = {
    code: string;
    value: string;
    description: string;
};

export type VibeProxyModelCatalog = {
    binary: string;
    providers: string[];
    models: VibeProxyModelOption[];
};

export function parseVibeProxyModelOutput(output: string): Map<string, string[]> {
    const catalog = new Map<string, string[]>();

    for (const line of output.split(/\r?\n/u)) {
        const match = /^([a-z][a-z0-9_-]*):\s*(.+)$/iu.exec(line.trim());
        if (!match) continue;

        // Compact command output may append a semicolon-delimited explanation.
        // Only the comma-delimited model segment belongs in the picker.
        const modelSegment = match[2].split(';', 1)[0];
        const models = modelSegment
            .split(',')
            .map((model) => model.trim())
            .filter((model) => model.length > 0);

        if (models.length > 0) {
            catalog.set(match[1].toLowerCase(), models);
        }
    }

    return catalog;
}

function proxyBinaryCandidates(): string[] {
    const configured = process.env.HAPPY_VIBEPROXY_BIN?.trim();
    const knownLocalDirectories = [
        join(os.homedir(), '.local', 'bin'),
        join(os.homedir(), '.cargo', 'bin'),
    ];
    const candidates = [
        ...(configured ? [configured] : []),
        ...DEFAULT_PROXY_BINARIES,
        ...knownLocalDirectories.flatMap((directory) =>
            DEFAULT_PROXY_BINARIES.map((binary) => join(directory, binary)),
        ),
    ];

    return [...new Set(candidates)].filter((candidate) =>
        !candidate.includes('/') || existsSync(candidate),
    );
}

async function runProxyCommand(binary: string, args: string[], timeout = COMMAND_TIMEOUT_MS): Promise<string> {
    const result = await execFileAsync(binary, args, {
        encoding: 'utf8',
        timeout,
        maxBuffer: COMMAND_MAX_BUFFER,
        windowsHide: true,
    });
    return result.stdout;
}

async function authenticatedProviders(binary: string, providers: string[]): Promise<string[]> {
    const configured = process.env.HAPPY_VIBEPROXY_PROVIDERS?.trim().toLowerCase();
    if (configured === 'all') return providers;
    if (configured) {
        const requested = new Set(configured.split(',').map((provider) => provider.trim()).filter(Boolean));
        return providers.filter((provider) => requested.has(provider));
    }

    const checks = await Promise.all(providers.map(async (provider) => {
        try {
            await runProxyCommand(binary, [provider, 'auth', 'status'], 2_500);
            return provider;
        } catch {
            return null;
        }
    }));
    const authenticated = checks.filter((provider): provider is string => provider !== null);

    // Third-party VibeProxy-compatible binaries may expose a model catalog but
    // not provider auth subcommands. In that case, preserve the useful catalog.
    return authenticated.length > 0 ? authenticated : providers;
}

export async function discoverVibeProxyModels(): Promise<VibeProxyModelCatalog | null> {
    for (const binary of proxyBinaryCandidates()) {
        try {
            const output = await runProxyCommand(binary, ['models', '--full']);
            const groupedModels = parseVibeProxyModelOutput(output);
            if (groupedModels.size === 0) continue;

            const providers = await authenticatedProviders(binary, [...groupedModels.keys()]);
            const seen = new Set<string>();
            const models = providers.flatMap((provider) =>
                (groupedModels.get(provider) ?? []).flatMap((model) => {
                    if (seen.has(model)) return [];
                    seen.add(model);
                    return [{
                        code: model,
                        value: model,
                        description: `${provider} via ${basename(binary)}`,
                    }];
                }),
            );

            if (models.length > 0) {
                return { binary, providers, models };
            }
        } catch {
            // Try the next compatible binary/path. Absence is expected for
            // regular Happy users who do not use this proxy-focused fork.
        }
    }

    return null;
}

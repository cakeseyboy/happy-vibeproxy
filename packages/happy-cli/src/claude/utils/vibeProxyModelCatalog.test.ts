import { describe, expect, it } from 'vitest';

import { parseVibeProxyModelOutput } from './vibeProxyModelCatalog';

describe('parseVibeProxyModelOutput', () => {
    it('parses every provider and preserves exact model IDs', () => {
        const catalog = parseVibeProxyModelOutput([
            'codex: gpt-5.6-sol, gpt-5.6-sol-fast, opus',
            'kimi: k2.6, kimi-for-coding',
            'grok: grok-4.5',
            'cursor: cursor:gpt-5.5, cursor-plan:composer-2.5',
        ].join('\n'));

        expect(catalog.get('codex')).toEqual(['gpt-5.6-sol', 'gpt-5.6-sol-fast', 'opus']);
        expect(catalog.get('kimi')).toEqual(['k2.6', 'kimi-for-coding']);
        expect(catalog.get('grok')).toEqual(['grok-4.5']);
        expect(catalog.get('cursor')).toEqual(['cursor:gpt-5.5', 'cursor-plan:composer-2.5']);
    });

    it('ignores compact-output explanations and unrelated log lines', () => {
        const catalog = parseVibeProxyModelOutput([
            'Proxy listening on http://127.0.0.1:18765',
            'cursor: composer-2.5, cursor-agent; 42 cursor model aliases run `models --full`',
            '',
        ].join('\n'));

        expect([...catalog.entries()]).toEqual([
            ['cursor', ['composer-2.5', 'cursor-agent']],
        ]);
    });

    it('deduplicates provider lines by keeping the latest complete line', () => {
        const catalog = parseVibeProxyModelOutput([
            'codex: gpt-5.5',
            'codex: gpt-5.5, gpt-5.6-luna',
        ].join('\n'));

        expect(catalog.get('codex')).toEqual(['gpt-5.5', 'gpt-5.6-luna']);
    });
});

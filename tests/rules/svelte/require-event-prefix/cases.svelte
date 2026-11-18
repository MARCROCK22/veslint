<script lang="ts">
	import type { ExternalProps } from './props';
	interface Props {
		click: () => void;
		onClick: () => void;
		submit(value: number): void;
		get: () => string;
		close?: () => undefined;
		load: () => Promise<void>;
		both: (() => void) | (() => null);
		mixed: (() => void) & { x: 1 };
		count: number;
	}
	let { click, onClick, submit, get, close, load, both, mixed, count }: Props = $props();
	let { select, onPick, label }: ExternalProps = $props();
	let all: { reset: () => void; ok: boolean } = $props();
	const notProps = $state(1);
</script>

<button onclick={click}>{count}{label}{all.ok}{notProps}</button>

<script lang="ts">
	let count = $state(0);
	const a = $derived.by(() => count * 2);
	const b = $derived.by(() => {
		return count + 1;
	});
	const c = $derived.by(function () {
		return count;
	});
	const d = $derived.by((): number => count);
	const e = $derived.by<number>((): number => count);
	const f = $derived.by<number>((): string => String(count));
	const g = $derived.by(() => (count, count + 1));
	const h = $derived.by(() => {
		return (count, 2);
	});
	const i = $derived.by(function () {
		return this;
	});
	const j = $derived.by(function named() {
		return named;
	});
	const k = $derived.by(function () {
		return arguments.length;
	});
	const l = $derived.by(() => /* keep */ count);
	const m = $derived.by(<T,>() => count as T);
	const n = $derived.by(() => {
		const x = count;
		return x;
	});
	const o = $derived.by(async () => count);
	const p = $derived.by((x = 1) => x);
	const q = $derived.by(() => ({ count }));
	const r = $derived.by(() => {
		return ((count));
	});
	const s = $derived(count);
	const u = $derived.by(() => {
		return;
	});
	const v = $derived.by(() => () => this);
	const w = $derived['by'](() => count);
	const z = $derived.by((): count is number => true);
</script>

<p>{a}{b}{c}{d}{e}{f}{g}{h}{i}{j}{k}{l}{m}{n}{o}{p}{q}{r}{s}{u}{v}{w}{z}</p>
<p>{$derived.by(() => count)}</p>

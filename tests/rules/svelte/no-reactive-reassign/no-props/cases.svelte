<script lang="ts">
	let source: { a: number; list: number[] } = { a: 1, list: [] };
	let n = 0;
	$: value = source;
	$: count = n * 2;
	$: items = [n];
	function update() {
		count = 1;
		count++;
		count += 2;
		value.a = 2;
		value.list.push(1);
		value['list'].sort();
		delete value.a;
		value?.list.reverse();
		(n ? count : n) = 3;
		[count] = [4];
		({ x: count } = { x: 5 });
		({ ...value } = source);
		for (count of [1]) {}
		for (count in {}) {}
		items.map((i) => i);
		value.list.length;
		items.push?.(3);
	}
	update;
</script>

<input bind:value={count} />
<input bind:value={value.a} />
<input bind:value />
<button onclick={() => (items = [])}>reset</button>
<p>{count} {value} {items}</p>

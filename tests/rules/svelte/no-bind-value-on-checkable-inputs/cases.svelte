<script lang="ts">
	const kind = 'checkbox';
	let other = 'radio';
	let changed = 'checkbox';
	changed = 'text';
	const parts = 'check';
	let value = $state('');
	let v2 = $state('');
	let flag = true;
	let items = ['radio'];
</script>

<input type={kind} bind:value />
<input type={other} bind:value={v2} />
<input type={changed} bind:value={v2} />
<input type={`${parts}box`} bind:value={v2} />
<input type={parts + 'BOX'} bind:value={v2} />
<input type={flag ? 'radio' : 'checkbox'} bind:value={v2} />
<input type="text" bind:value={v2} />
<input type="checkbox" bind:checked={flag} />
<input type="checkbox{''}" bind:value={v2} />
<input Type="Radio" bind:value|preventDefault={v2} />
<input bind:value={v2} type="checkbox" />
{#each items as t (t)}
	<input type={t} bind:value={v2} />
{/each}
{#if flag}
	{@const k = 'radio'}
	<input type={k} bind:value={v2} />
{/if}
<input type="checkbox" {...{}} bind:value={v2} />

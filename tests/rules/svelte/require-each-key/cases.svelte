<script lang="ts">
	const items = [{ id: 1, name: 'a' }];
</script>

{#each items as item}
	<p>{item.name}</p>
{/each}
{#each items as item, i}
	<p>{i}</p>
{/each}
{#each items as item (item.id)}
	<p>{item.name}</p>
{/each}
{#each items as { id, name }}
	<p>{id}{name}</p>
{/each}
{#each items}
	<p>no item</p>
{/each}
{#each items as item, index (index)}<p>{item.id}</p>{/each}
<ul>
	{#each items as
		item
	}
		<li>{item.id}</li>
	{:else}
		<li>none</li>
	{/each}
</ul>

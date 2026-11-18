<script lang="ts">
	const items = [{ id: 1, name: 'a' }];
	const other = 1;
</script>

{#each items as item (item.id)}<p>{item.name}</p>{/each}
{#each items as item, i (i)}<p>{item.name}</p>{/each}
{#each items as item (other)}<p>{item.name}</p>{/each}
{#each items as item (`${other}`)}<p>{item.name}</p>{/each}
{#each items as { id, name } (id)}<p>{name}</p>{/each}
{#each items as { id, name } (other + 1)}<p>{name}</p>{/each}
{#each items as item (items.indexOf(item))}<p>{item.id}</p>{/each}
{#each items.map((x) => x.id) as id (id)}<p>{id}</p>{/each}
{#each items as item ((() => item.id)())}<p>{item.id}</p>{/each}
{#each items as item ((() => other)())}<p>{item.id}</p>{/each}

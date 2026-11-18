<script lang="ts">
	const a = () => {};
	const b = () => {};
</script>

<button on:click={a} on:click={a}>x</button>
<button on:click={a} on:click={b}>x</button>
<button on:click on:click>x</button>
<button on:click={a} on:click>x</button>
<button
	on:click={() => a()}
	on:keydown={a}
	on:click={() => a()}
	on:click={()=>a()}
>x</button>
<button on:click|once={a} on:click={a}>x</button>
<Comp on:custom={a} on:custom={a} />

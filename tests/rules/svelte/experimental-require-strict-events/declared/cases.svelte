<script lang="ts">
	interface $$Events { x: CustomEvent<void> }
	import { createEventDispatcher } from 'svelte';
	const dispatch = createEventDispatcher();
</script>

<button on:click={() => dispatch('x')}>x</button>

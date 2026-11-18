<script lang="ts">
	import { createEventDispatcher } from 'svelte';

	const dispatch = createEventDispatcher();
	const typed = createEventDispatcher<{ done: string }>();
	dispatch('done');
	typed('done', 'x');
</script>

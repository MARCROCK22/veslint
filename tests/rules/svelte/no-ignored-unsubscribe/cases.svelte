<script lang="ts">
	import { writable } from 'svelte/store';

	const store = writable(0);
	store.subscribe(() => {});
	const unsubscribe = store.subscribe(() => {});
	unsubscribe();
	store?.subscribe(() => {});
	store['subscribe'](() => {});
	(store.subscribe)(() => {});
	class Holder {
		#subscribe() {}
		run() {
			this.#subscribe();
		}
	}
	new Holder().run();
	void store.subscribe(() => {});
</script>

<button onclick={() => store.subscribe(() => {})}>{$store}</button>

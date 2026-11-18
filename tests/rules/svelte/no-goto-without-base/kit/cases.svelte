<script lang="ts">
	import { goto } from '$app/navigation';
	import { goto as go } from '$app/navigation';
	import * as navigation from '$app/navigation';
	import { base } from '$app/paths';
	import { base as root } from '$app/paths';

	const path = '/foo';
	goto('/foo');
	goto(base + '/foo');
	goto(`${base}/foo`);
	goto(`/foo/${base}`);
	goto('https://example.com');
	goto('mailto:someone@example.com');
	goto(path);
	go(root + '/bar');
	go('/bar' + root);
	navigation.goto('/baz');
	goto(`${root}`);
	goto(1);
	goto();
	goto(`${path}/x`);
	goto(base);
</script>

<button onclick={() => goto('/template')}>go</button>

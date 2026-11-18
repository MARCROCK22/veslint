<script lang="ts">
	import { goto, pushState, replaceState } from '$app/navigation';
	import { base } from '$app/paths';
	import * as paths from '$app/paths';

	const prefixed = base + '/x';
	const alsoPrefixed = `${prefixed}/y`;
	const plain = '/z';
	goto('/foo');
	goto(base + '/foo');
	goto(`${base}/foo`);
	goto(prefixed);
	goto(alsoPrefixed);
	goto(plain);
	goto('https://example.com');
	goto(...[base]);
	pushState('', {});
	pushState('/bar', {});
	pushState(`${base}/bar`, {});
	replaceState(``, {});
	replaceState('/baz', {});
	replaceState(base, {});
</script>

<a href="/foo">a</a>
<a href="{base}/foo">b</a>
<a href={base + '/foo'}>c</a>
<a href="https://example.com">d</a>
<a href="#top">e</a>
<a href={'#' + 'top'}>f</a>
<a href={`mailto:${plain}`}>g</a>
<a href={plain}>h</a>
<a href={prefixed}>i</a>
<link href="/x" rel="stylesheet" />
<A href="/y">k</A>

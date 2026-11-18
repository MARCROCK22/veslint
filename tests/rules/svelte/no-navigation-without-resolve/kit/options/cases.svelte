<script lang="ts">
	import { goto, pushState, replaceState } from '$app/navigation';
	import { resolve, asset } from '$app/paths';
	import type { ResolvedPathname } from '$app/types';

	const resolved = resolve('/about');
	const typed: ResolvedPathname = '/about';
	const notTyped: string = '/x';
	const paths = [resolve('/'), resolve('/about')] as const;
	const map = { home: resolve('/'), other: '/other' };
	const links = [{ href: resolve('/') }, { href: resolve('/about') }];
	const bad = [{ href: '/a' }];
	const maybe: ResolvedPathname | undefined = undefined;
	goto(resolve('/about'));
	goto('/about');
	goto(resolved);
	goto(typed);
	goto(notTyped);
	goto(paths[0]);
	goto(map.home);
	goto(map.other);
	goto(cond() ? resolve('/') : '/b');
	goto(cond() ? resolve('/') : resolved);
	goto(asset('/img.png'));
	goto(`${resolved}`);
	goto(maybe ?? '/');
	pushState('', {});
	pushState('/p', {});
	replaceState(``, {});
	replaceState(resolve('/'), {});
	function cond() {
		return true;
	}
	let href = '/z';
</script>

<!-- Links decided before their type is looked at (ESLint's type check of a link needs the
     `typescript` package the plugin loads from here to be TypeScript 5/6). -->
<a href="/about">a</a>
<a href="https://example.com">c</a>
<a href="#top">d</a>
<a href={undefined}>e</a>
<a href={null}>f</a>
<a href="/ext" rel="external">h</a>
<a href="/ext" rel="noopener {'external'}">i</a>
<a href="/ext" rel={`no ${'external'}`}>i2</a>
<a href="mailto:x@example.com">i3</a>
<link href="/x" rel="stylesheet" />

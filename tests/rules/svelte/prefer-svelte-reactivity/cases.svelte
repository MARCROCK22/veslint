<script lang="ts">
	let runes = $state(0);
	const date = new Date();
	date.setFullYear(2000);
	const fixedDate = new Date();
	fixedDate.getTime();
	const map = new Map<string, number>();
	map.set('a', 1);
	const set = new Set<number>();
	set.add(1);
	const readOnlySet = new Set([1]);
	readOnlySet.has(1);
	const url = new URL('https://example.com');
	url.pathname = '/x';
	const readUrl = new URL('https://example.com');
	readUrl.pathname;
	const params = new URLSearchParams();
	params.append('a', 'b');
	let reassigned = new Map();
	reassigned = new Map();
	reassigned.clear();
	const viaGlobal = new globalThis.Set();
	viaGlobal.delete(1);
	const notConstructed = Set;
	function make() {
		const inner = new Map();
		inner.delete('a');
		return inner;
	}
	make;
	export const exported = new Set();
</script>

<p>{runes}{date}{fixedDate}{map}{set}{readOnlySet}{url}{readUrl}{params}{reassigned}{viaGlobal}{notConstructed}{exported}</p>

<script lang="ts" module>
	let shared = new Set<number>();
	shared = new Set<number>();
	shared.add(1);
	const first = new Date();
	const second = new Date();
	first.setDate(1);
	second.setDate(2);
	const alias = first;
	alias.setHours(1);
	const third = new Date();
	const otherAlias = third;
	otherAlias.setHours(2);
	let urlA = new URL('https://a.example');
	urlA = new URL('https://b.example');
	urlA.hash = 'x';
	const { set: destructured } = { set: new Set() };
	destructured.add(1);
</script>

<script lang="ts">
	let a: unknown;
	let n = 0;
	$: a = 'foo';
	$: a = 1;
	$: a = [];
	$: a = {};
	$: a = null;
	$: a = /re/g;
	$: a = 10n;
	$: a = [1];
	$: a = { b: 1 };
	$: a = `x`;
	$: n += 1;
	$: a = n, n = 2;
	$: a = -1;
	$: {
		a = 2;
	}
	$: a = 'with comment' // c
	$: a = true
</script>

<p>{a} {n}</p>

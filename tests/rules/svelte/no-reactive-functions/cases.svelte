<script lang="ts">
	let a: unknown;
	let n = 0;
	$: a = () => n;
	$: a = function () {
		return n;
	};
	$: a = async () => n;
	$:a = () => 1;
	$: /* c */ a = () => 2;
	$:/* c */a = () => 3;
	$: a = n > 0 ? () => n : null;
	$: a = (() => n)();
	$: a = (() => n);
	$: n += 1;
</script>

<p>{a} {n}</p>

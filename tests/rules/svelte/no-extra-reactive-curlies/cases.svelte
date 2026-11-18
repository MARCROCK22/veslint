<script lang="ts">
	let a = 0;
	let b = 0;
	$: {
		a = b * 2;
	}
	$: { a = b; }
	$: {
		// a comment
		a = 1;
		/* trailing */
	}
	$: {
		a = 1;
		b = 2;
	}
	$: {}
	$: a = b;
	$: if (a) {
		b = 1;
	}
	$: { { b = a; } }
</script>

<p>{a} {b}</p>

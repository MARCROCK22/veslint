<script lang="ts">
	// eslint-disable-next-line no-var
	var first = 1;
	/* eslint-disable eqeqeq */
	const same = first == 1;
	/* eslint-enable eqeqeq */
	const other = first == 2; // eslint-disable-line
	let third = 3;
</script>

<!-- eslint-disable-next-line -->
<p>{same} {other} {third == 3}</p>

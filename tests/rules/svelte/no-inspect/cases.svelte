<script lang="ts">
	let count = $state(0);
	$inspect(count);
	$inspect(count).with(console.trace);
	const alias = { $inspect: 1 };
	alias.$inspect;
	function run() {
		$inspect.trace();
	}
	run;
</script>

<p>{count} {$inspect}</p>

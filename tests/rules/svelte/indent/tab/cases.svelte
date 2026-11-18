<script lang="ts">
	let a = 1;
  let b = 2;
	  let c = 3;
	function f() {
		return [
			a,
		  b,
		];
	}
</script>

<div>
	<span>{a}</span>
  <span>{b}</span>
    {#if c}
		<i>{f()}</i>
	{/if}
</div>

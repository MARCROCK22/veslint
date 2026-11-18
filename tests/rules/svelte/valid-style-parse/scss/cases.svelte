<script lang="ts">
	let x = 1;
</script>

<div class="a">{x}</div>

<style lang="scss">
	$c: red;
	.a {
		// a comment
		color: $c;
		&:hover { color: #{$c}; }
		font: { family: x; }
	}
	.b { color: "unclosed }
</style>

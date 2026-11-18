<script lang="ts">
	let a = 1;
</script>

<div class="a"></div>
<div class="a" title="b"></div>
<div class="a" title="b" id="c"></div>
<div
	class="a"
	title="b"
></div>
<div
	class="a" title="b"
	id="c"
></div>
<div class="a"
	title="b" id="c" {a}></div>
<input bind:value={a} on:input={() => {}} {...{}} style:color="red" />
<div
	class="a" title="b" id="c" data-x="d"
></div>
<div class="a
	b" title="c"
	id="d"></div>

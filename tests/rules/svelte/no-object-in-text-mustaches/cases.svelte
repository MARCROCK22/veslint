<script lang="ts">
	const a = 1;
</script>

<p>{{ a }}</p>
<p>{[a]}</p>
<p>{() => a}</p>
<p>{function () { return a; }}</p>
<p>{class X {}}</p>
<p>{a}</p>
<input value={{ a }} />
<input value="x{{ a }}" />
<input value={[a]} />
<div style:color={{ a }}></div>
{@html { a }}
<p>{(({ a }))}</p>

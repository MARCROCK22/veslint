<script lang="ts">
	const html: string = '<b>hi</b>';
	const other = { value: '<i>x</i>' };
</script>

{@html html}
<div>{@html other.value}</div>
<p>{html}</p>
{#if html}
	{@html `${html}!`}
{/if}
<span title={html}>{@html
	html + html}</span>

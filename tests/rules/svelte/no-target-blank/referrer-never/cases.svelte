<script lang="ts">
	let url = 'https://example.com';
	let href = url;
</script>

<a href="https://example.com" target="_blank">external</a>
<a href="//example.com" target="_blank">protocol relative</a>
<a href="mailto:a@b.c" target="_blank">mailto</a>
<a href="/local" target="_blank">local</a>
<a href={url} target="_blank">dynamic</a>
<a href="{url}/x" target="_blank">dynamic text</a>
<a {href} target="_blank">shorthand</a>
<a bind:href={href} target="_blank">bind</a>
<a href="https://example.com" target="_blank" rel="noopener noreferrer">secure</a>
<a href="https://example.com" target="_blank" rel="NOOPENER NoReferrer">secure upper</a>
<a href="https://example.com" target="_blank" rel="noopener">noopener only</a>
<a href="https://example.com" target="_blank" rel="noreferrer">noreferrer only</a>
<a href="https://example.com" target="_self">self</a>
<a href="https://example.com" target={'_blank'}>dynamic target</a>
<a href="https://example.com"
	target="_blank"
>multi-line</a>

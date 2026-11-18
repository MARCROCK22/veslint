<script lang="ts">
	let kind: 'button' | 'submit' = 'button';
	const rest = { type: 'button' as const };
	let bound = 'reset';
</script>

<button>no type</button>
<button type="button">ok</button>
<button type="submit">ok</button>
<button type="reset">ok</button>
<button type="">empty</button>
<button type>boolean</button>
<button type="foo">invalid</button>
<button type="{kind}">dynamic</button>
<button type={kind}>dynamic</button>
<button type="sub{kind}">mixed</button>
<button {...rest}>spread</button>
<button bind:type={bound}>bind</button>
<button {kind} class="x">shorthand of another name</button>
<button
	class="multi"
	>multi-line</button>
<Button>component</Button>
<div><button on:click={() => {}}>nested</button></div>

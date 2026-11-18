<script lang="ts">
	const name = 'header';
	const alias = name;
	const joined = 'a' + `b${name}`;
	let dynamic = 'x';
	const { destructured } = { destructured: 'y' };
</script>

<slot name={name}></slot>
<slot name="{alias}"></slot>
<slot name="pre-{name}"></slot>
<slot name={joined}></slot>
<slot name={dynamic}></slot>
<slot name={destructured}></slot>
<slot name></slot>
<slot name="static"></slot>
<slot name={'literal'}></slot>
<div name={name}></div>

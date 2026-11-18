<script lang="ts">
	let value = '';
	let active = true;
	let color = 'red';
</script>

<input bind:value={value} />
<input bind:value />
<input bind:value="{value}" />
<input bind:value={active} />
<div class:active={active}></div>
<div class:active></div>
<div class:active="{active}"></div>
<div style:color={color}></div>
<div style:color="{color}"></div>
<div style:color></div>
<div style:color="{color} "></div>
<div style:color={active}></div>
<div on:click={value}></div>
<input bind:value={ value } />

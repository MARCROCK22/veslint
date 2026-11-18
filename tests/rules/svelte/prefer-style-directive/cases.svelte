<script lang="ts">
	let c = 'red';
	let t = true;
</script>

<div style="color: red"></div>
<div style="color: red; background: blue"></div>
<div style="color: red; background: {c}; top: 1px"></div>
<div style="color: red !important; top: 0"></div>
<div style="{c}: red"></div>
<div style="color: red" style:color="blue"></div>
<div style="color: red;"></div>
<div style="color: {t ? 'red' : 'blue'}"></div>
<div style="{t ? 'color: red' : ''}"></div>
<div style="top: 0; {t ? '' : 'color: red'}"></div>
<div style="{t ? 'color: red' : ''}; top: 0"></div>
<div style="{t ? 'color: red; top: 0' : ''}"></div>
<div style="{t ? 'color: red' : 'top: 0'}"></div>
<div style={t ? 'color: red' : ''}></div>
<Comp style="color: red" />
<svelte:element this={'div'} style="color: red"></svelte:element>
<div style="/* x */ color: red"></div>
<div style="color: red; /* x */"></div>
<div
	style="
		color: red;
		top: 0;
	"
></div>
<div style="é: ü; color: red"></div>

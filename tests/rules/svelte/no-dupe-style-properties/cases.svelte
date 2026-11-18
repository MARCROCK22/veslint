<script lang="ts">
	let c = 'red';
	let t = true;
</script>

<div style="color: red; color: blue"></div>
<div style="color: red" style:color={c}></div>
<div style="color: red; background: {c}; color: green; color: blue"></div>
<div style="color: red; {t ? 'color: blue' : 'color: green'}"></div>
<div style="{t ? 'top: 1px' : 'top: 2px'}; top: 3px"></div>
<div style={`color: ${c}; color: red`}></div>
<div style="color: {c}; {`color: ${c}`}"></div>
<div style="color: red; /* color: blue */ background: x"></div>
<div style="é: 1; é: 2"></div>
<Comp style="color: red; color: blue" />
<div
	style="
		margin: 0;
		margin: 1px;
	"
></div>
<div style="a: {t && 'b: c'} ; b: d"></div>

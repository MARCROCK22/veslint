<script lang="ts">
	let style = 'color: red';
	let p = 'color';
	let c = 'red';
	let t = true;
</script>

<div {style}></div>
<div style="color: red"></div>
<div style="{p}: red"></div>
<div style="color: {c}"></div>
<div style="color: red; /* x */"></div>
<div style="color: red; {t ? 'a: b' : ''}"></div>
<div style={style}></div>
<div style="color: red {c} x: y"></div>
<div style="a {c}: b"></div>
<div style=""></div>
<div style></div>
<Comp style="a: {c}" />
<div style="@media x {'{'} a: b {'}'}"></div>
<div style="a{'{'}b: c{'}'}"></div>

<script lang="ts">
	let c = 'red';
</script>

<div style:color={c}></div>
<div style:colour={c}></div>
<div style:--custom={c}></div>
<div style:-webkit-foo={c}></div>
<div style:-moz-bar="x"></div>
<div style:unknown-prop="x"></div>
<div style:Color="x"></div>
<div style:my-prop|important="x"></div>
<span style:bad-é="x"></span>
<Comp style:nope="x" />

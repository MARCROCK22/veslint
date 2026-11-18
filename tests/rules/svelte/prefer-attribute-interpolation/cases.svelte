<script lang="ts">
	const a = 'x';
	const b = 1;
</script>

<div title={`${a}`}></div>
<div title={`pre ${a} post`}></div>
<div title={`no expressions`}></div>
<div title={`${a}
${b}`}></div>
<div title={`{${a}}`}></div>
<div title={`tab\t${a}`}></div>
<div title={`quote\'${a}`}></div>
<div title={/* c */ `${a}`}></div>
<div title="x{`${a}`}"></div>
<div style:color={`${a}`}></div>

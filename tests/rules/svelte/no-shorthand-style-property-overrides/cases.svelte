<script lang="ts">
	let c = 'red';
	let t = true;
</script>

<div style="margin-top: 1px; margin: 0"></div>
<div style="margin: 0; margin-top: 1px"></div>
<div style:margin-left="1px" style="margin: 2px"></div>
<div style="-webkit-flex-grow: 1; -webkit-flex: 1"></div>
<div style="flex-grow: 1; -webkit-flex: 1"></div>
<div style="background-color: {c}; background: none; border-top-width: 1px; border: 0"></div>
<div style="font-size: 1px; {t ? 'font: x' : ''}"></div>
<div style="grid-row-gap: 1px" style:grid-gap="2px"></div>
<div style="padding-left: 0; padding: 0; padding: 1px"></div>
<Comp style="margin-top: 1px; margin: 0" />

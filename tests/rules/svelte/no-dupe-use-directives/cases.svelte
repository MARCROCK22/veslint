<script lang="ts">
	const tooltip = (node: HTMLElement, text?: string) => {};
	const other = (node: HTMLElement) => {};
</script>

<div use:tooltip use:tooltip></div>
<div use:tooltip={'a'} use:tooltip={'a'}></div>
<div use:tooltip={'a'} use:tooltip={'b'}></div>
<div use:tooltip use:other></div>
<div
	use:tooltip={'x'}
	use:other
	use:tooltip={ 'x' }
></div>

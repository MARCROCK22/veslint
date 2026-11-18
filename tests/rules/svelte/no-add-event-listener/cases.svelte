<script lang="ts">
	const button = document.createElement('button');
	button.addEventListener('click', () => {});
	window.addEventListener('resize', () => {}, { passive: true });
	addEventListener('scroll', () => {});
	document.body.addEventListener /* c */ ('keydown', () => {});
	button?.addEventListener('focus', () => {});
	button.addEventListener?.('blur', () => {});
	button['addEventListener']('input', () => {});
	button.removeEventListener('click', () => {});
	(button).addEventListener('change', () => {});
	globalThis.addEventListener<'load'>('load', () => {});
</script>

<button onclick={() => button.addEventListener('click', () => {})}>x</button>

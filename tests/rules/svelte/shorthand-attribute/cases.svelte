<script lang="ts">
	let title = 'x';
	let src = '';
	const value = 1;
</script>

<div title={title}></div>
<div title="{title}"></div>
<div title='{title}'></div>
<img src={src} alt="" />
<div title={src}></div>
<div {title}></div>
<input value={value} />
<input value={ value } />
<div title="{title} "></div>
<Comp value={value} />
<div title=
	{title}></div>

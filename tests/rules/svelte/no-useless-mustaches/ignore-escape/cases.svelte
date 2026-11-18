<script lang="ts">
	const a = 1;
</script>

<p>{'text'}</p>
<p>{"text"}</p>
<p>{`text`}</p>
<p>{`te${a}xt`}</p>
<p>{'<b>'}</p>
<p>{' padded '}</p>
<p>{'a\nb'}</p>
<p>{'a\\b'}</p>
<p>{'a\'b'}</p>
<p>{'{'}</p>
<p>{/* c */ 'text'}</p>
<p>{`line
break`}</p>
<p>{1}</p>
<div title={'x'}></div>
<div title="{'x"y'}"></div>
<div title='{"x&y"}'></div>
<div title="a{'b'}c"></div>
<div style:color={'red'}></div>
{@html 'raw'}
<p>{''}</p>

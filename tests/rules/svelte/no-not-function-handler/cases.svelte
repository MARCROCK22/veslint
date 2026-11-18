<script lang="ts">
	const handler = () => {};
	const obj = { a: 1 };
	const str = 'x';
	const alias = obj;
	let changing = 1;
</script>

<button on:click={handler}>ok</button>
<button on:click={{}}>object</button>
<button on:click={[]}>array</button>
<button on:click={class {}}>class</button>
<button on:click={'s'}>string</button>
<button on:click={1}>number</button>
<button on:click={true}>boolean</button>
<button on:click={null}>null</button>
<button on:click={/re/}>regex</button>
<button on:click={10n}>bigint</button>
<button on:click={`t`}>template</button>
<button on:click={obj}>const object</button>
<button on:click={alias}>alias</button>
<button on:click={str}>const string</button>
<button on:click={changing}>let</button>
<button onclick={obj}>attribute</button>
<button onclick="{str}">quoted</button>
<button onmouseover={{}}>attribute object</button>
<button data-x={{}}>not an event</button>
<button on:click>forward</button>

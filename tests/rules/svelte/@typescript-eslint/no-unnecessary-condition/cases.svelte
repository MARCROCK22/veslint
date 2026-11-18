<script lang="ts">
  export let maybe: string | undefined = undefined;
  let mutable = 0;
  const fixed = { a: 1, b: null as string | null };
  const list: number[] = [1, 2];
  const tuple: [number, string] = [1, 'a'];
  const big = 0n;
  const branded = 'x' as string & { brand: true };
  const nothing = null;

  if (fixed) {
    console.log(fixed?.a, fixed.b?.length);
  }
  const c1 = fixed.a ?? 0;
  const c2 = nothing ?? 1;
  const c3 = maybe ?? 'x';
  const c4 = list[0] ?? 2;
  const c5 = !fixed && maybe;
  const c6 = 1 === 1;
  const c7 = fixed.a === undefined;
  const c8 = list.filter((n) => n);
  const c9 = list.find(() => true);
  const c10 = list.some(function () {
    return 'yes';
  });
  const c11 = big ? 1 : 2;
  const c12 = branded ? 1 : 2;
  const c13 = tuple.every(() => 0);
  const c14 = fixed.b?.toString();
  const c15 = list?.[0];

  $: reactive = mutable ? 'a' : 'b';
  $: reactiveFixed = fixed ? 'a' : 'b';
  $: if (mutable && fixed) {
    console.log(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15);
  }
</script>

{#if fixed}
  <p>{fixed ? 'yes' : 'no'}</p>
{/if}
<p>{mutable ? 'yes' : 'no'}</p>
<p>{maybe ?? 'none'}</p>
<p>{fixed.a ?? 'none'}</p>
<p>{fixed?.a}</p>
<p>{list.filter((n) => mutable)}</p>
<p>{reactive}{reactiveFixed}</p>

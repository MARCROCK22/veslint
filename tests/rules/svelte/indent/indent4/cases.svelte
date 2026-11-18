<script lang="ts">
  let a = 1;
    function f(x: number) {
      return x +
          1;
    }
</script>

<div>
  <span
      class="x"
  >{a}</span>
    {#if a}
        <b>{f(a)}</b>
    {/if}
</div>

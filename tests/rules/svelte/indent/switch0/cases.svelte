<script lang="ts">
  function f(x: number) {
    switch (x) {
    case 1:
      return 'a';
      case 2:
      return 'b';
    default:
        return 'c';
    }
  }
</script>

<p>{f(1)}</p>

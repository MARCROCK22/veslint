<script lang="ts">
  let n = 0;
  while (true) {
    n++;
    if (n > 3) break;
  }
  const flag = false;
  do {
    n--;
  } while (flag);
  for (; 1; ) {
    break;
  }
</script>

<p>{n}</p>

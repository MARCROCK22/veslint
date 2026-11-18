<script lang="ts">
export default {
  watch: {
    a: () => {},
    b() {},
    c: { handler: () => {}, deep: true },
    d: [() => {}, 'm', { handler: () => {} }, function () {}],
    'e.f': async () => {},
    ...{ g: () => {} },
    [`h`]: (x: number) => x,
  },
}
</script>

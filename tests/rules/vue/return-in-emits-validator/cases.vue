<script lang="ts">
export default {
  emits: {
    a: () => false,
    b: (x: number) => x > 0,
    c() {
      return undefined
    },
    d() {},
    e: function () {
      if (Math.random()) {
        return true
      }
      return false
    },
    f() {
      const g = () => true
      g()
      return 0
    },
    ['h' + 1]: () => null,
    i: () => 0n,
  },
}
</script>

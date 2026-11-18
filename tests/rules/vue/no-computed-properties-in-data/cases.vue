<script lang="ts">
export default {
  data() {
    const a = this.foo
    const b = this.bar
    const c = () => this.foo
    return { a, b, c, d: this.baz }
  },
  computed: {
    foo() {
      return 1
    },
    baz: {
      get() {
        return 2
      },
    },
  },
}
</script>

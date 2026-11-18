<script lang="ts">
export default {
  props: {
    a: {
      type: String,
      default() {
        return this.b
      },
    },
    c: {
      type: Function,
      default() {
        return this.d
      },
    },
    e: {
      default: function () {
        function inner(this: any) {
          return this.f
        }
        const g = () => this.h
        return inner
      },
    },
    i: { type: [String, Function], default() { return this.j } },
    k: { default: () => (this as any).l },
  },
}
</script>

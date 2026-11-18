<script lang="ts">
declare const api: { get(): Promise<number> }
declare const Vue: any
export default {
  computed: {
    async one(): Promise<number> {
      await api.get()
      return 1
    },
    two(): number {
      api.get().then(() => {})
      Promise.all([])
      new Promise(() => {})
      setTimeout(() => {}, 1)
      window.requestAnimationFrame(() => {})
      this.$nextTick(() => {})
      Vue.nextTick(() => {})
      return 2
    },
    three: {
      get(): number {
        Promise.resolve(1)
        return 3
      },
    },
  },
}
</script>

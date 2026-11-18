<script lang="ts">
import { nextTick } from 'vue'
declare const Vue: { nextTick: (cb?: () => void) => Promise<void> }
export default {
  async mounted() {
    this.$nextTick(() => {})
    Vue.nextTick(() => {})
    nextTick(() => {})
    await nextTick()
    nextTick().then(() => {})
    nextTick()
    this.$nextTick
    const a = nextTick
    nextTick(() => {}, 1)
    await nextTick(() => {})
    return nextTick()
  },
  methods: {
    f() {
      return Promise.all([nextTick(), Vue.nextTick])
    },
  },
}
</script>

<script lang="ts">
import { watch, watchEffect, ref } from 'vue'
declare function doSomething(): Promise<void>
export default {
  async setup() {
    const a = ref(1)
    watch(a, () => {})
    await doSomething()
    watch(a, () => {})
    watchEffect(() => {})
    const stop = watch(a, () => {})
    const handles = [watchEffect(() => {})]
    return { stop, handles }
  },
}
</script>

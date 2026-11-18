<script lang="ts">
import { onMounted, onUnmounted, onBeforeMount } from 'vue'
declare function doSomething(): Promise<void>
declare const instance: any
export default {
  async setup() {
    onBeforeMount(() => {})
    await doSomething()
    onMounted(() => {})
    onUnmounted(() => {}, instance)
    const f = async () => {
      await doSomething()
      onMounted(() => {})
    }
    return { f }
  },
}
</script>

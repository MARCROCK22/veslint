import { defineComponent, onUpdated } from 'vue'
declare function doSomething(): Promise<void>
export default defineComponent({
  async setup() {
    await doSomething()
    onUpdated(() => {})
  },
})

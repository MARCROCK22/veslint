import { defineComponent, nextTick } from 'vue'
declare const cond: boolean
export default defineComponent({
  setup() {
    const f = cond ? nextTick : null
    ;(cond ? nextTick : nextTick)()
    nextTick.call(null)
    return { f }
  },
})

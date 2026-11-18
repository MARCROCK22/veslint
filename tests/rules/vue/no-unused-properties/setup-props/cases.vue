<script lang="ts">
// @ts-nocheck
import { defineComponent, toRefs, toRef } from 'vue'
import { external } from './external'
function local(p) { return p.l1 }
export default defineComponent({
  props: { a: String, b: String, c: String, d: String, e: String, f: String, g: String, l1: String, l2: String },
  setup(props) {
    const { a } = toRefs(props)
    const bRef = toRef(props, 'b')
    external(props)
    local(props)
    const { c, ...rest } = props
    return { a, bRef, c, rest }
  },
  render(h, { props }) {
    return h('div', props.d)
  },
})
</script>

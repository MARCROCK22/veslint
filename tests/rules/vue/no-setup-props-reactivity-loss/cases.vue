<script lang="ts">
import { watch, computed } from 'vue'
export default {
  props: { a: String, b: Object },
  setup(props: { a?: string; b?: { c: number } }) {
    const { a } = props
    const b = props.b
    const c = props.b?.c
    const arr = [props.a]
    const obj = { a: props.a }
    const t = `${props.a}`
    const cond = props.a ? 1 : 2
    watch(props.a, () => {})
    const ok = computed(() => props.a)
    let x
    x = props.a
    return { a, b, c, arr, obj, t, cond, ok, x }
  },
}
</script>

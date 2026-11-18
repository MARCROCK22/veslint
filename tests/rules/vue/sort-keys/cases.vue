<script lang="ts">
export default {
  name: 'A',
  data() {
    return {
      z: 1,
      a: 2,
    }
  },
  props: {
    z: { type: String, required: true, default: 'x' },
    a: String,
  },
  model: { prop: 'x', event: 'y' },
  computed: {
    b() {
      return { y: 1, x: 2 }
    },
  },
}
const obj = { b: 1, a: 2, ...x, d: 1, c: 3, [k]: 1, B: 2, C10: 1, C9: 2 }
declare const x: object
declare const k: string
</script>

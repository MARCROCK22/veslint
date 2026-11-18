<script lang="ts">
import Vue from 'vue'
export default {
  data() {
    return { a: 1, list: [] as number[], obj: {} as Record<string, number> }
  },
  computed: {
    one(): number {
      this.a = 2
      this.a++
      this.list.push(1)
      this.list?.sort()
      delete this.obj.x
      Object.assign(this.obj, {})
      this.$set(this.obj, 'x', 1)
      Vue.set(this.obj, 'x', 1)
      const nested = () => { this.a = 3 }
      return this.a
    },
    two: {
      get(): number {
        this.a = 4
        return 1
      },
    },
  },
}
</script>

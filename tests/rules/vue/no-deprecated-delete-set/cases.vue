<script lang="ts">
import { set, del as remove } from 'vue'
export default {
  mounted() {
    this.$set(this.a, 'b', 1)
    this.$delete(this.a, 'b')
    Vue.set(this.a, 'b', 1)
    Vue.delete(this.a, 'b')
    const vm = this
    vm.$set(vm.a, 'b', 1)
    this.$set
  },
}
set({}, 'a', 1)
remove({}, 'a')
declare const Vue: any
</script>

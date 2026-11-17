<script setup lang="ts">
const vm: any = {}
vm.$set(vm, 'a', 1)
Vue.set(vm, 'a', 1)
const c = defineComponent({
  mounted() {
    this.$delete(this, 'a')
  },
})
declare const Vue: any
</script>

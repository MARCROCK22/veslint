<script lang="ts">
export default {
  mounted() {
    this.$on('a', () => {})
    this.$off('a')
    this.$once('a', () => {})
    this.$on?.('a', () => {})
    this?.$on('a', () => {})
    ;(this?.$off)('a')
    const vm = this
    vm.$on('b', () => {})
    this['$once']('c')
    this.$emit('d')
    foo.$on('e')
    let other = this
    other.$on('f')
  },
}
declare const foo: any
</script>

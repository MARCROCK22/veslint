<script lang="ts">
export default {
  emits: { used: null, unused: (a: number) => true, 'quoted-unused': null, [dyn]: null, ...rest },
  methods: {
    m() {
      this.$emit('used')
      const vm = this
      vm.$emit('viaVm')
    }
  }
}
</script>

<script lang="ts">
export default {
  beforeRouteEnter(to: any, from: any, next: any) {
    this.a
    const f = () => this.b
    function g(this: any) {
      return this.c
    }
    next((vm: any) => {
      vm.d = this
    })
  },
  beforeRouteLeave() {
    this.e
  },
}
</script>

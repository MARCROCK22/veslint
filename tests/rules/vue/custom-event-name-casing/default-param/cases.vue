<script lang="ts">
export default {
  setup(props, ctx = {} as any) {
    ctx.emit('with-default')
  },
}
</script>

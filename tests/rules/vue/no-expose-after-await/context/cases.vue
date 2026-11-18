<script lang="ts">
declare function doSomething(): Promise<void>
export default {
  async setup(_: unknown, ctx: { expose: (o: object) => void }) {
    await doSomething()
    ctx.expose({})
    ctx?.expose({})
  },
}
</script>

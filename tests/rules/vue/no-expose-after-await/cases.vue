<script lang="ts">
declare function doSomething(): Promise<void>
export default {
  async setup(_: unknown, { expose }: { expose: (o: object) => void }) {
    expose({})
    await doSomething()
    expose({})
  },
}
</script>

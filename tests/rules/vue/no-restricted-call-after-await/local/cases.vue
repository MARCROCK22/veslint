<script lang="ts">
import { bar } from './foo'
import lib from './lib'
import { baz } from './foo'
declare function doSomething(): Promise<void>
export default {
  async setup() {
    await doSomething()
    bar()
    baz()
    lib()
  },
}
</script>

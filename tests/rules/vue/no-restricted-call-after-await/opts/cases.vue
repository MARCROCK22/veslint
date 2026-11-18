<script lang="ts">
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'
declare function doSomething(): Promise<void>
export default {
  async setup() {
    useI18n()
    await doSomething()
    useI18n()
    useRoute()
  },
}
</script>

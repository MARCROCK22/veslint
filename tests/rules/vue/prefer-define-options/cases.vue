<script lang="ts">
export default { name: 'Foo', inheritAttrs: false }
</script>
<script setup lang="ts">
import { ref } from 'vue'
import type { Ref } from 'vue'
const a: Ref<number> = ref(1)
</script>

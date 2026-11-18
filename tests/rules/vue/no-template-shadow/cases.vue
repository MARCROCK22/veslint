<template>
  <div>
    <div v-for="item in items" :key="item">
      <span v-for="item in item.children" :key="item">{{ item }}</span>
      <p v-for="(a, i) in list" :key="i">{{ a }}</p>
    </div>
    <comp v-slot="{ msg, ok }">{{ msg }}{{ ok }}</comp>
    <comp v-slot="{ allowed }">{{ allowed }}</comp>
    <i v-for="i in 3" :key="i" />
    <i v-for="Typed in 3" :key="Typed" />
    <i v-for="fromProp in 3" :key="fromProp" />
    <i v-for="extra in 3" :key="extra" />
  </div>
</template>
<script setup lang="ts">
import { ref } from 'vue'
interface Typed { a: number }
const msg = ref('')
defineProps<{ fromProp: string }>()
function list() {}
</script>
<script lang="ts">
export default {
  data() { return { ok: true, a: 1 } },
  computed: { extra() { return 1 } },
}
</script>

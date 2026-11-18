<script setup lang="ts">
import { computed } from 'vue'
type S = 'a' | 'b'
declare const s: S
const a = computed(() => {})
const b = computed({
  get() {
    if (s === 'a') return 1
  },
  set(v: number) {},
})
const c = computed(() => {
  switch (s) {
    case 'a':
      return 1
    case 'b':
      return 2
  }
})
const d = computed(() => 1)
</script>

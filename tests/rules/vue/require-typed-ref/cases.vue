<script setup lang="ts">
import { ref, shallowRef, type Ref } from 'vue'
const a = ref()
const b = ref(null)
const c = shallowRef(undefined)
const d = ref<number>()
const e: Ref<number | undefined> = ref()
const f = ref(1)
const g = ref() as Ref<string>
function take(x: Ref<number | undefined>, ...rest: Ref[]) {}
take(ref(), ref())
let h: Ref<string | undefined>
h = ref()
const i = ({ j = ref() }: { j?: Ref<number | undefined> }) => j
</script>

<script setup lang="ts" generic="T extends string, U">
import { ref, computed } from "vue";

import Unused from "./both-scripts.vue";
import MyThing from "./single-script.vue";
import {load, maybe} from "./util";

const props = withDefaults(defineProps<{"item": T;
other?: U;
size?: number }>(),
{ size: 1 });
const emit = defineEmits<(e: "change", value: T) => void>();
const model = defineModel<string>();
const inputRef = ref<HTMLInputElement | null>(null);
const vFocus = {"mounted": (el: HTMLElement) => {
  el.focus();
}};
const label = ref("a");
const total = computed(() => props.size * 2);
const unused = 1;

async function save (value: T) {
  load(1);
  if (maybe) {
    emit("change",
value);
  }
  await load(2);
  return value;
}

defineExpose({ save });
</script>

<template>
  <MyThing
    ref="inputRef"
    v-focus
    :label="label"
    @click="save(props.item)"
  >
    {{ total }} {{ model }}
  </MyThing>
</template>

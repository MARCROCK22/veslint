<script setup lang="ts" generic="T extends string, U">
import { ref, computed } from 'vue';
import { load, maybe } from './util';
import MyThing from './single-script.vue';
import Unused from './both-scripts.vue';

const props = withDefaults(defineProps<{ item: T; other?: U; size?: number }>(), { size: 1 });
const emit = defineEmits<{ (e: 'change', value: T): void }>();
const model = defineModel<string>();
const inputRef = ref<HTMLInputElement | null>(null);
const vFocus = { mounted: (el: HTMLElement) => el.focus() };
let label = ref('a');
var total = computed(() => props.size * 2);
const unused = 1;

async function save(value: T) {
  load(1);
  if (maybe) {
    emit('change', value);
  }
  await load(2);
  return value as T;
}

defineExpose({ save });
</script>

<template>
  <my-thing v-focus ref="inputRef" :label="label" @click="save(props.item)">
    {{ total }} {{ model }}
  </my-thing>
</template>

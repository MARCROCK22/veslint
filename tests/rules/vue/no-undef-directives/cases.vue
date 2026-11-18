<template>
  <div v-focus v-my-dir:arg.mod="x" v-other v-if="x" v-Upper v-snake_case v-ignored-one v-model="x" />
  <input v-local v-from-import v-cap-name />
</template>
<script setup lang="ts">
import vFromImport from './dir'
const vLocal = {}
const x = 1
</script>
<script lang="ts">
export default {
  directives: { focus: {}, 'my-dir': {}, CapName: {}, ...spread }
}
</script>

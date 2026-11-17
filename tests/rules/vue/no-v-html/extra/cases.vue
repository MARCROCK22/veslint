<script setup lang="ts">
const héllo = "<b>ü</b>"
</script>

<template>
  <p title="ü😀" v-html="héllo"></p>
  <p v-html></p><span v-HTML="x" V-html="y"></span>
  <p v-else-if="a" v-html="`${a}`" />
</template>

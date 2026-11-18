<template>
  <div :class="{ a  :  b }" :style="{ c :  d }">
    {{ x }}    <!-- eol comment -->
    <span  />    <!-- eol -->
  </div>
</template>
<script setup lang="ts">
const b = 1
const d = 2
const x = 3
</script>

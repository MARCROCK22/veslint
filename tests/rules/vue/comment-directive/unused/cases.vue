<!-- eslint-disable -->
<template>
  <!-- eslint-disable vue/no-v-html , vue/no-v-text -->
  <div v-html="a"></div>
  <!-- eslint-enable -->
  <div v-text="a"></div> <!-- eslint-disable-line -->
  <!-- eslint-disable-next-line vue/no-v-text, vue/no-v-html -- reason -->
  <div v-html="b"></div>
  <p>{{ a /* eslint-disable-line foo */ }}</p>
  <!--eslint-disable-line   ,,  vue/x -->
  <!-- éé eslint-disable -->
  <!-- 😀 --><!-- eslint-disable-next-line 😀 -->
  <!--
    eslint-disable-line
  -->
</template>
<!-- eslint-disable-next-line vue/no-v-html -->
<script setup lang="ts">
const a = 1
const b = 2
</script>
<!-- eslint-enable -->

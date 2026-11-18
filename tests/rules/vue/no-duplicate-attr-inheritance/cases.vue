<template>
  <div v-bind="$attrs" />
  <div v-bind:foo="$attrs" />
  <div v-bind="{ ...$attrs, a: $attrs }" />
  <div v-for="$attrs in list" v-bind="$attrs" />
</template>
<script lang="ts">
export default {}
</script>

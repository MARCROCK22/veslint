<script lang="ts">
export default {
  name: "SyntaxErrorSetup",
}
</script>

<script setup lang="ts">
const c = 1
const = 2
</script>

<template>
  <p>{{ c }}</p>
</template>

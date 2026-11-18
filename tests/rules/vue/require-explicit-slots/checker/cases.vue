<template>
  <slot name="named" />
  <slot name="missing" />
</template>
<script setup lang="ts">
import type { Slots } from './cases'
defineSlots<Slots>()
</script>

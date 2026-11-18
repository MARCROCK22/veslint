<template>
  <div>
    <the-button />
    <TheCard />
    <foo_bar />
    <component is="IsAttr" />
    <component is="vue:VueIs" />
    <component :is="'BoundIs'" />
    <div v-is="'VIsComp'" />
  </div>
</template>
<script lang="ts">
import { defineComponent } from 'vue'
export default defineComponent({
  components: {
    TheButton: {},
    theCard: {},
    foo_bar: {},
    Unused: {},
    IsAttr: {},
    VueIs: {},
    BoundIs: {},
    VIsComp: {},
    'kebab-unused': {},
    ['Computed']: {},
    ...spread,
  }
})
</script>

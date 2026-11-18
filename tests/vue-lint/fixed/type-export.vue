<script lang="ts">
export default { name: 'TypeExport' }
</script>

<script setup lang="ts">
// vue-eslint-parser rewrites `export { … }` of a <script setup> next to a <script> as `( … );`:
// a type-only specifier makes code TypeScript rejects, a parsing error of the whole file.
const café = 'é'
type Label = string
export { café, type Label as Name }
</script>

<template><p>{{ café }}</p></template>

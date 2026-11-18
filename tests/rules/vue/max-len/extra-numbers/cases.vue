<script setup lang="ts">
const a = 1 // first trailing comment // that goes on and on and on and on and on
const b = 2 /* one */ /* two, a trailing comment that goes on and on and on and on */
/* a block
   comment whose lines go on and on and on and on and on and on and on and on and on and on */
const c = 3 /* starts here
   and ends here, a long line, a long line, a long line, a long line */ const d = 4
// IGNORE: this line goes on and on and on and on and on and on and on and on and on and on
</script>

<template>
  <div>{{ a /* comment in an expression that goes on and on and on and on and on */ }}</div>
  <!-- an HTML comment that goes on and on and on and on and on and on and on and on and on -->
  <div :title="'a string in the template that goes on and on and on and on and on and on'" />
  <div>{{ `a template in the template that goes on and on and on and on and on and on` }}</div>
</template>

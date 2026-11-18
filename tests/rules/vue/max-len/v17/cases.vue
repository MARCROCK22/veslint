
<template>
  <div :class="{
         'foo': /regexploooooooooooooooooooooooooooooooooooooooooooong/.test(bar)
       }">
  </div>
</template>
<script lang="ts">
var a = /regexploooooooooooooooooooooooooooooooooooooooooooooooooooooong/.test(b)
</script>

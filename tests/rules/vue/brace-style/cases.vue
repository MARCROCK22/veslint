<template>
  <div @click="if (a)
  {
    b()
  }
  else {
    c()
  }" />
  <div :a="function ()
  {
    return 1
  }" />
  <div @click="() => { a() }" />
  <div @click="{a();b();}" />
</template>

<script setup lang="ts">
if (Math.random())
{
  console.log(1)
}
</script>

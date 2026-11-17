<template>
  <div @click="if(a){b()}else{c()}" />
  <p>{{ typeof(a) }}</p>
  <div :a="a instanceof(B)" />
  <div @click="for(const x of list){use(x)}" />
  <div @click="() => {return(1)}" />
</template>

<script setup lang="ts">
if(Math.random()){console.log(1)}
</script>

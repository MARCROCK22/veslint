<template>
  <p>{{ fn( a ) }}</p>
  <div :a="( b )" />
  <div @click="fn( )" />
  <div v-for="( item, index ) in list" :key="index" />
  <div :[fn( a )]="x" />
</template>

<script setup lang="ts">
console.log( 1 )
</script>

<style>
.a {
  width: v-bind("fn( w )");
}
</style>

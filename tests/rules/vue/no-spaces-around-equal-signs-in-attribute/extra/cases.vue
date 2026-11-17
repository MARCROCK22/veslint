<script setup lang="ts">
const ü = "😀"; const fooBar = 1
</script>
<template>
  <p title="ü😀" v-bind:foo-bar="fooBar" :a="ü" v-bind:ü="ü">{{ü}}{{  "😀"  }}</p>
  <input @keyup.13="ü" @keyup.ü.32="ü" class = "x" :b =  "ü"/>
  <i>é</i><b :c="fooBar" .d="ü">{{/* c */ü/* d */}}</b>
</template>

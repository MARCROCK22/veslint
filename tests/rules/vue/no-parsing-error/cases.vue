<script setup lang="ts">
const a = 1
</script>

<template>
  <div :a="a,b" :b="...c" :c="c +" :d="d d" v-if=" " @click=" ">
    {{ a b c }}
    <p v-for="foo() in list">{{ x }}</p>
    <p v-for="x">{{ x }}</p>
    <p v-show="a;b;">{{ (a }}</p>
    <p :[a b]="1" v-slot:[x.]="y" #default="{ a: }"></p>
    <p @click="foo(" v-on:keyup="a = " :x="<T>(y)"></p>
    <p>{{ a ?? }} {{ }} {{ 'é' + }}</p>
  </div>
</template>

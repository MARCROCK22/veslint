<template>
  <div><component v-bind:is="type"></component></div>
  <div><component :is="type"></component></div>
  <div><component is="type"></component></div>
  <div><component v-foo:is="type"></component></div>
</template>

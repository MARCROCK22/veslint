<template>
  <div><div :class="[{'foo': isFoo}]" /></div>
  <div><div :class="[{'foo': isFoo, 'bar': isBar}]" /></div>
  <div><div v-foo:class="[{'foo': isFoo}, {'bar': isBar}]" /></div>
  <div><div v-bind:class="[{'foo': isFoo}, {'bar': isBar}]" /></div>
  <div><div :class="[{'foo': isFoo}, {'bar': isBar}]" /></div>
  <div><div v-bind:class="[,{'foo': isFoo}, {'bar': isBar}]" /></div>
</template>

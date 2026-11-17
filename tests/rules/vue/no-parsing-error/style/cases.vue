<template>
  <div>{{ color }}</div>
</template>
<style>
.text {
  color: v-bind(color.);
  background: v-bind('a b');
}
</style>

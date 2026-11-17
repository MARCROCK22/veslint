<template>
  <p>{{ a == b }}</p>
  <div :a="a != null" />
  <div v-if="typeof a == 'string'" />
  <div :a="1 == 2" />
</template>

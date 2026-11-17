<template>
  <p>{{ fn(a) }}</p>
  <div @click="fn()" />
  <div :a="fn( b )" />
</template>

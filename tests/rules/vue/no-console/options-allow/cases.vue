<template>
  <p>{{ console.log(1) }}</p>
  <div @click="console.warn('x')" />
  <div :a="console[`warn`]" />
</template>

<template>
  <p>{{ -a }}</p>
  <div :a="!b" />
  <div :a="typeof a" />
  <div @click="++i" />
</template>

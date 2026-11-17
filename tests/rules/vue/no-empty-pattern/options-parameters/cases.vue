<template>
  <div @click="({}) => 1" />
  <div @click="function ({}) { return 1 }" />
  <div @click="const {} = $event" />
</template>

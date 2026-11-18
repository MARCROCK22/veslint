<template>
  <p>{{ a ? b : c }}</p>
  <div :a="a
    ? b
    : c" />
</template>

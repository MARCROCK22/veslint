<template>
  <p>{{ !!foo }}</p>
  <div :a="`${foo}`" />
  <div :a="+foo" />
</template>

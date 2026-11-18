<template>
  <div :a="{ a }" />
  <div :a="{ f() { return 1 } }" />
</template>

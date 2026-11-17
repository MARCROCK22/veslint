<template>
  <div :a="{ 'a-b': function () {} }" />
  <div :a="{ x: x, y: () => 1 }" />
</template>

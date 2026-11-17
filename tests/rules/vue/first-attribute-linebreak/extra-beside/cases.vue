<template>
  <div><!-- c -->
    <span a="1"
      b="2"></span>
    <span
      a="1" b="2"></span>
    <span a="1" b="2"></span>
    <span
      a="1"></span>
    <MyComp :a="x"
      @b="y" v-if="z"
    />
    <MyComp v-bind="{ a: 1,
      b: 2 }" />
  </div>
</template>

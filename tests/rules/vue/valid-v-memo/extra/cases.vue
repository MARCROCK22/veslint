<template>
  <div>
    <div v-for="x in xs" :key="x">
      <div v-memo="[x]" />
      <div>
        <span v-memo:arg.mod1.mod2="[x]" />
      </div>
    </div>
    <div v-for="y in ys" v-memo="[y]" :key="y" />
    <div v-memo />
    <div v-memo="" />
    <div v-memo="  " />
    <div v-memo="a = 1, b ? {} : (c as D)" />
    <div v-memo="cond ? [a] : `t`" />
    <div v-memo="-1" />
    <div v-memo="x++" />
    <div v-memo="new Foo()" />
    <div v-memo="a!" />
    <div v-memo="(class {})" />
  </div>
</template>

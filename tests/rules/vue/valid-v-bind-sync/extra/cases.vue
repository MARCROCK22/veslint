<template>
  <div>
    <div :foo.sync="a" />
    <MyComp :foo.sync="a?.b" :bar.sync="(a?.b).c" :baz.sync="null.x" :qux.sync="(1n).x" :q2.sync="a.b.c" :q3.sync="a + b" :q4.sync="a[b]" :q5.sync="(a as any).b" :q6.sync />
    <MyComp v-for="(x, i) in xs" :key="i" :a.sync="x" :b.sync="x.y" :c.sync="i" :d.sync="xs[i]" />
    <MyComp #default="{ s }"><Other :e.sync="s" /></MyComp>
    <component :is="c" :foo.sync="a" />
    <MyComp v-bind.sync="obj" :f.sync="a!" />
  </div>
</template>

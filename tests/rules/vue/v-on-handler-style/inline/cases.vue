<template>
  <div>
    <button @click="foo()" />
    <button @click="bar()" />
    <button @click="baz(1)" />
    <button @click="a = 1; b()" />
    <button @click="foo" />
    <button @click="() => foo()" />
    <button @click="(e) => bar(e)" />
    <button @click="function () { foo() }" />
    <button @click="foo($event)" />
    <button @click='single()' />
    <template v-for="e in list"><button @click="foo(e)" /><button @click="() => go(e)" /></template>
    <button @click="{ foo(); }" />
    <button @click="x(); y();" />
    <button v-on="{ click: foo }" />
  </div>
</template>
<script setup lang="ts">
function foo() {}
const bar = (e?: unknown) => {}
const list = [1]
function baz(...a: number[]) {}
</script>
<script lang="ts">
export default { methods: { single() {}, go(e: unknown) {} } }
</script>

<template>
  <div>
    <div v-if="a" /><div v-else-if="a" />
    <div v-if="a || b" /><div v-else-if="b" /><div v-else-if="a && c" />
    <div v-if="a" /><span /><div v-else-if="a" />
    <div v-if="a" />
    text
    <div v-else-if="a" />
    <div v-if="a" />  <!-- c -->  <div v-else-if="a" />
    <div v-if="(a)" /><div v-else-if="a" />
    <div v-if="a && b" /><div v-else-if="b && a" /><div v-else-if="c && (a && b)" />
    <div v-if="a | f" /><div v-else-if="a | f" />
    <div v-if /><div v-else-if="a" /><div v-else-if="a" />
    <div v-else-if="x" /><div v-else-if="x" />
    <div v-if="a" /><div v-else /><div v-else-if="a" />
    <div v-if="a ?? b" /><div v-else-if="b ?? a" /><div v-else-if="a ?? b" />
  </div>
</template>

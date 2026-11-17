<template>
  <div>{{ msg }}</div>
  <div>{{ method(msg) }}</div>
  <div>{{ msg | filter }}</div>
  <div>{{ msg | filter }}</div>
  <div>{{ msg | filter(x) }}</div>
  <div>{{ msg | filterA | filterB }}</div>
  <div><div v-for="msg in messages">{{ msg | filter }}</div></div>
  <div><div v-bind:id="msg | filter"></div></div>
  <div><div v-bind:id="msg | filter(aaa)"></div></div>
  <div><div v-bind:id="msg | filterA | filterB"></div></div>
</template>

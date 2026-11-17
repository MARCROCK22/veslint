<template>
  <div @click="while (true) { a() }" />
  <div @click="for (;1;) { a() }" />
</template>

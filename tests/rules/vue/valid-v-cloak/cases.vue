<template>
  <div><div v-cloak></div></div>
  <div><div v-cloak:aaa></div></div>
  <div><div v-cloak.aaa></div></div>
  <div><div v-cloak="aaa"></div></div>
  <div><div v-cloak="."></div></div>
  <div><div v-cloak="/**/" /></div>
  <div><div v-cloak="" /></div>
</template>

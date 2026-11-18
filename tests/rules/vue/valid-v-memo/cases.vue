<template>
  <div><div v-memo="[x]"></div></div>
  <div><div v-memo="x"></div></div>
  <div><div v-memo="x?y:z"></div></div>
  <div><div v-memo="." /></div>
  <div><div v-memo="/**/" /></div>
  <div><div v-for="i in items" v-memo="[x]"></div></div>
  <div><div v-memo:aaa="x"></div></div>
  <div><div v-memo.aaa="x"></div></div>
  <div><div v-memo></div></div>
  <div><div v-memo="" /></div>
  <div>
        <div v-memo="{x}" />
        <div v-memo="a ? {b}: c+d" />
        <div v-memo="(a,{b},c(),d+1)" />
        <div v-memo="()=>42" />
        <div v-memo="a=42" />
      </div>
  <div><div v-for="i in items"><div v-memo="[x]" /></div></div>
</template>

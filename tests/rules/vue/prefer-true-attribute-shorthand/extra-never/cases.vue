<template>
  <div>
    <MyComp :a="true" b v-bind:c="true" v-model:d="true" :e="false" :f="'true'" g="" :h-i="true" v-on:j="true" :[k]="true" v-model="true" />
    <div :a="true" b />
  </div>
</template>

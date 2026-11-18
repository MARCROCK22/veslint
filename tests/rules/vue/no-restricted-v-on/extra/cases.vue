<template>
  <div>
    <MyComp @click="a" v-on:click.prevent="b" @[ev]="c" v-on="d" @Click.stop.once="e" />
    <div @click.self="f" @keyup.enter="g" />
  </div>
</template>

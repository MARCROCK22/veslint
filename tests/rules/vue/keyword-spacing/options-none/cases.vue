<template>
  <div @click="if (a) { b() } else { c() }" />
  <div @click="if(a){b()}else{c()}" />
</template>

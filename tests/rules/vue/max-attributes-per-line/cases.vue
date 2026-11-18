<template>
  <div><component></component></div>
  <div><component
        name="John Doe"
        age="30"
        job="Vet"
      ></component></div>
  <div><component
        name="John Doe"
        age="30"
      >
      </component></div>
  <div><component job="Vet"
        name="John Doe"
        age="30">
        </component>
      </div>
  <div><component name="John Doe" age="30"></component></div>
  <div><component :name="user.name" :age="user.age"></component></div>
  <div><component :is="test" v-bind="user"></component></div>
  <div><component :name="user.name" @buy="buyProduct"></component></div>
  <div><component :name="user.name" @click.stop></component></div>
  <div><component :name="user.name" v-if="something"></component></div>
  <div><component name="John Doe"    v-bind:age="user.age"></component></div>
</template>

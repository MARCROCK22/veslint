<template>
  <div>
        <NuxtLink tag="div" to="/">Home</NuxtLink>
      </div>
  <div>
        <nuxt-link tag="div" to="/">Home</nuxt-link>
      </div>
  <div>
        <NuxtLink :tag="someVariable" to="/">Home</NuxtLink>
      </div>
  <div>
        <nuxt-link :tag="someVariable" to="/">Home</nuxt-link>
      </div>
</template>

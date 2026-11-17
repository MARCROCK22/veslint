<template>
  <div>
        <RouterLink to="/">Home</RouterLink>
      </div>
  <div>
        <router-link to="/">Home</router-link>
      </div>
  <div>
        <RouterLink to="/">
          <div>Home</div>
        </RouterLink>
      </div>
  <div>
        <router-link to="/">
          <div>Home</div>
        </router-link>
      </div>
  <div>
        <NuxtLink to="/">Home</NuxtLink>
      </div>
  <div>
        <nuxt-link to="/">Home</nuxt-link>
      </div>
  <div>
        <NuxtLink to="/">
          <div>Home</div>
        </NuxtLink>
      </div>
  <div>
        <nuxt-link to="/">
          <div>Home</div>
        </nuxt-link>
      </div>
  <div>
        <RouterLink tag="div" to="/">Home</RouterLink>
      </div>
  <div>
        <router-link tag="div" to="/">Home</router-link>
      </div>
  <div>
        <RouterLink :tag="someVariable" to="/">Home</RouterLink>
      </div>
  <div>
        <router-link :tag="someVariable" to="/">Home</router-link>
      </div>
</template>

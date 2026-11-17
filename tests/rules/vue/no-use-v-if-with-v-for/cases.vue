<template>
  <div><div v-if="shown"><div v-for="(x,i) in list"></div></div></div>
  <div>
          <ul>
            <li
              v-for="user in activeUsers"
              :key="user.id"
            >
              {{ user.name }}
            <li>
          </ul>
        </div>
  <div>
          <ul v-if="shouldShowUsers">
            <li
              v-for="user in users"
              :key="user.id"
            >
              {{ user.name }}
            <li>
          </ul>
        </div>
  <div><div v-if="shown"><div v-for="({x,y,z},i) in list"></div></div></div>
  <div>
          <ul>
            <li
              v-for="{user} in activeUsers"
              :key="user.id"
            >
              {{ user.name }}
            <li>
          </ul>
        </div>
  <div>
          <ul v-if="shouldShowUsers">
            <li
              v-for="{user} in users"
              :key="user.id"
            >
              {{ user.name }}
            <li>
          </ul>
        </div>
  <div><div><div v-for="x in list" v-if="shown"></div></div></div>
  <div><div><div v-for="x in list" v-if="list.length&gt;0"></div></div></div>
  <div><div><div v-for="x in list" v-if="x.isActive"></div></div></div>
  <div>
          <ul>
            <li
              v-for="user in users"
              v-if="user.isActive"
              :key="user.id"
            >
              {{ user.name }}
            <li>
          </ul>
        </div>
  <div>
          <ul>
            <li
              v-for="user in users"
              v-if="shouldShowUsers"
              :key="user.id"
            >
              {{ user.name }}
            <li>
          </ul>
        </div>
  <div><div><div v-for="{x,y,z} in list" v-if="z.isActive"></div></div></div>
  <div>
          <ul>
            <li
              v-for="{foo, bar, user} in users"
              v-if="user.isActive"
              :key="user.id"
            >
              {{ user.name }}
            <li>
          </ul>
        </div>
  <div>
          <ul>
            <li
              v-for="{foo, bar, user} in users"
              v-if="shouldShowUsers"
              :key="user.id"
            >
              {{ user.name }}
            <li>
          </ul>
        </div>
  <div><div><div v-for="{x} in list()" v-if="x.isActive"></div></div></div>
  <div><div><div v-for="i in 5" v-if="i"></div></div></div>
</template>

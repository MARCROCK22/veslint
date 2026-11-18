<template>
  <div>
        <div
          v-for="a in items"
          v-if="a"
          attr="a">
        </div>
      </div>
  <div>
        <div
          v-if="a"
          attr="a"
          v-for="a in items">
        </div>
      </div>
  <div>
        <div
          attr="a"
          v-if="a"
          v-for="a in items">
        </div>
      </div>
</template>

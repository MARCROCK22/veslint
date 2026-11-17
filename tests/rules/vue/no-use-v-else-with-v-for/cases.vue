<template>
  <div>
          <div v-if="foo" v-for="x in xs">{{ x }}</div>
        </div>
  <div>
          <div v-if="foo">{{ x }}</div>
          <div v-else-if="foo">{{ x }}</div>
          <div v-else="foo">{{ x }}</div>
        </div>
  <div>
          <div v-for="x in xs">{{ x }}</div>
        </div>
  <div>
          <div v-if="foo">foo</div>
          <template v-else-if="bar">
            <div v-for="x in xs">{{ x }}</div>
          </template>
          <template v-else>
            <div v-for="x in xs">{{ x }}</div>
          </template>
        </div>
  <div>
          <div v-if="foo">foo</div>
          <div v-else v-for="x in xs">{{ x }}</div>
        </div>
  <div>
          <div v-if="foo">foo</div>
          <div v-else-if="bar" v-for="x in xs">{{ x }}</div>
        </div>
</template>

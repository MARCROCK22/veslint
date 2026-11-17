<template>
  <div>
        <div v-text="content" />
      </div>
  <div>
        <div v-html="content" />
      </div>
  <div>
        <MyComponent v-if="content" />
      </div>
  <div>
        <svg><g v-text="content" /></svg>
        <math><mspace v-text="content" /></math>
      </div>
  <div>
        <MyComponent v-text="content" />
      </div>
  <div>
        <MyComponent v-html="content" />
      </div>
  <div>
        <component :is="component" v-text="content" />
      </div>
  <div>
        <component :is="component" v-html="content" />
      </div>
  <div>
        <div :is="component" v-text="content" />
      </div>
  <div>
        <div :is="component" v-html="content" />
      </div>
</template>

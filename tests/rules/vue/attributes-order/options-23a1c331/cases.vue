<template>
  <div>
            <div
              v-if="!visible"
              v-for="item in items"
              v-once
              is="header"
              v-on:click="functionCall"
              ref="header"
              :prop="headerData"
              v-text="textContent"
              id="uniqueID"
              myProp="prop"
              >
            </div>
          </div>
</template>

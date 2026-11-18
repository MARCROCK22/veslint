<template>
  <div>
          <div
            v-if="!visible"
            v-for="item in items"
            v-once
            is="header"
            v-on:click="functionCall"
            ref="header"
            v-text="textContent"
            id="uniqueID"
            :prop="headerData"
            myProp="prop"
            >
          </div>
        </div>
</template>

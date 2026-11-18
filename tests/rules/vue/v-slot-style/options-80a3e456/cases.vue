<template>
  <div>
          <template>
            <my-component v-slot:default="data">
              <template v-slot:default></template>
              <template v-slot:foo></template>
            </my-component>
          </template>
        </div>
</template>

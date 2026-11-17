<template>
  <div>
          <template>
            <my-component v-slot="data">
              <template #default></template>
              <template #foo></template>
            </my-component>
          </template>
        </div>
</template>

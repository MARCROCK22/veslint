<template>
  <div>
          <template>
            <my-component v-slot="data">
              <template #default></template>
              <template v-slot:foo></template>
            </my-component>
          </template>
        </div>
  <div>
          <template>
            <my-component>
              <template v-slot:[default]></template>
            </my-component>
          </template>
        </div>
  <div>
          <my-component>
            <template #foo></template>
          </my-component>
        </div>
  <div>
          <my-component>
            <template #[foo]></template>
          </my-component>
        </div>
</template>

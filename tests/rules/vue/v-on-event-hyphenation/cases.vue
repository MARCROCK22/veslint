<template>
  <div>
        <VueComponent @custom-event="onEvent"/>
    </div>
  <div>
        <VueComponent :customEvent="onEvent"/>
    </div>
  <div>
        <VueComponent v-on="events"/>
    </div>
  <div>
        <div v-on:unknownEvent="onEvent"/>
    </div>
  <div>
          <VueComponent @customEvent="onEvent"/>
      </div>
</template>

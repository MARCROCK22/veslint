<template>
  <div>
      <LinkList>
        <one :slot="name" />
        <my-component v-bind:slot="name" />
      </LinkList>
    </div>
</template>

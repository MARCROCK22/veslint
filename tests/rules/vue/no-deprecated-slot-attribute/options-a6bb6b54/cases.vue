<template>
  <div>
      <LinkList>
        <one slot="one" />
        <two slot="two" />
        <my-component slot="my-component-slot" />
        <myComponent slot="myComponent-slot" />
        <MyComponent slot="MyComponent-slot" />
      </LinkList>
    </div>
  <div>
      <LinkList>
        <one :slot="name" />
        <template v-bind:slot="name"><a /></template>
      </LinkList>
    </div>
</template>

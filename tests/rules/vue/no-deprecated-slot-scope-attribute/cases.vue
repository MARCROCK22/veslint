<template>
  <div>
      <LinkList>
        <template v-slot:name><a /></template>
      </LinkList>
    </div>
  <div>
      <LinkList>
        <template #name><a /></template>
      </LinkList>
    </div>
  <div>
      <LinkList>
        <template v-slot="{a}"><a /></template>
      </LinkList>
    </div>
  <div>
      <LinkList v-slot="{a}">
        <a />
      </LinkList>
    </div>
  <div>
      <LinkList>
        <template #default="{a}"><a /></template>
      </LinkList>
    </div>
  <div>
      <LinkList>
        <a slot="name" />
      </LinkList>
    </div>
  <div>
      <LinkList>
        <template><a /></template>
      </LinkList>
    </div>
  <div>
        <LinkList>
          <template slot-scope="{a}"><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template slot-scope><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <a slot-scope="{a}" />
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template slot-scope="{a}" slot="foo"><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template slot-scope="{a}" :slot="arg"><a /></template>
        </LinkList>
      </div>
  <div>
        <my-component>
          <template v-for="x in xs" slot-scope="{a}" >
          {{a}}
          </template>
        </my-component>
      </div>
  <div>
        <my-component>
          <template slot-scope="{a}" >
            {{a}}
          </template>
          <div />
        </my-component>
      </div>
</template>

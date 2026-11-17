<template>
  <div>
      <LinkList>
        <a v-slot:name />
      </LinkList>
    </div>
  <div>
      <LinkList>
        <a #name />
      </LinkList>
    </div>
  <div>
      <LinkList>
        <a v-slot="{a}" />
      </LinkList>
    </div>
  <div>
      <LinkList>
        <a #default="{a}" />
      </LinkList>
    </div>
  <div>
      <LinkList>
        <a slot="name" />
      </LinkList>
    </div>
  <div>
      <LinkList>
        <a slot-scope="{a}" />
      </LinkList>
    </div>
  <div>
      <LinkList>
        <a />
      </LinkList>
    </div>
  <div>
        <LinkList>
          <template scope="{a}">
            <a />
          </template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template slot="name" scope="{a}">
            <a />
          </template>
        </LinkList>
      </div>
</template>

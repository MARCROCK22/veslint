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
        <template><a /></template>
      </LinkList>
    </div>
  <div>
      <LinkList>
        <a />
      </LinkList>
    </div>
  <div>
        <LinkList>
          <template slot ><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template slot="name" ><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template slot="name" unknown slot-scope="{a}" ><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template slot="name" scope="{a}"><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template slot="nameFoo"><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template slot="f o o" ><a /></template>
          <template slot="obj.prop" ><a /></template>
          <template slot="a/b" ><a /></template>
          <template slot="a=b" ><a /></template>
          <template slot="a>b" ><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template v-bind:slot=name><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template :slot="slot.name"><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template :slot="  slotName  "><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template :slot="slot. name"><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template :slot="a>b?c:d"><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template :slot="  "><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template :slot="  .error  "><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <template :slot><a /></template>
        </LinkList>
      </div>
  <div>
        <LinkList>
          <a slot="name" />
        </LinkList>
      </div>
  <div>
        <LinkList>
          <a :slot="name" />
        </LinkList>
      </div>
  <div>
        <MyComponent>
          <template slot="foo-bar">
            <a/>
          </template>
        </MyComponent>
      </div>
  <div>
        <MyComponent>
          <template slot="foo_bar">
            <a/>
          </template>
        </MyComponent>
      </div>
  <div>
        <MyComponent>
          <template slot="123">
            <a/>
          </template>
        </MyComponent>
      </div>
  <div>
        <some-component>
          <template slot="some-slot">
            This works 1
          </template>

          <template v-if="true"> <!-- some arbitrary conditional -->
            <template slot="some-slot">
              This works 2
            </template>
          </template>
        </some-component>
      </div>
  <div>
        <my-component>
          <template v-for="x in xs" slot="one">
            A
          </template>
          <template v-for="x in xs" :slot="x">
            B
          </template>
        </my-component>
      </div>
  <div>
        <my-component>
          <template slot="one">
            A
          </template>
          <template slot="one">
            B
          </template>
        </my-component>
      </div>
  <div>
        <my-component>
          <template v-if="c" slot="one">
            A
          </template>
          <template v-else slot="one">
            B
          </template>
        </my-component>
      </div>
  <div>
        <my-component>
          <template v-for="x in xs" :slot="x">
            A
          </template>
          <template v-for="x in xs" :slot="x">
            B
          </template>
        </my-component>
      </div>
  <div>
        <my-component>
          <template v-for="x in ys" :slot="x">
            A
          </template>
          <template v-for="x in xs" :slot="x">
            B
          </template>
        </my-component>
      </div>
  <div>
        <my-component>
          <template v-for="(x,y) in xs" :slot="x+y">
            A
          </template>
          <template v-for="x in xs" :slot="x">
            B
          </template>
        </my-component>
      </div>
  <div>
        <my-component>
          <slot
            v-for="slot in Object.keys($slots)"
            :slot="slot"
            :name="slot"
          ></slot>
        </my-component>
      </div>
  <div>
        <component :is="toggle ? 'my-component' : 'div'">
          <div slot="named">
            Passing in a named slot to a div worked with old syntax
            But not with new syntax
          </div>
        </component>
      </div>
</template>

<template>
  <div>
        <my-component>
          <one slot="one">
            A
          </one>
        </my-component>
        <my-component2>
          <two slot="two">
            B
          </two>
        </my-component2>
      </div>
  <div>
        <my-component>
          <one :slot="one">
            A
          </one>
        </my-component>
        <my-component2>
          <two :slot="two">
            B
          </two>
        </my-component2>
      </div>
</template>

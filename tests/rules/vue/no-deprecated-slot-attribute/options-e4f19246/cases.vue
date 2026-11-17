<template>
  <div>
        <my-component>
          <one slot="one">
            A
          </one>
          <two slot="two">
            B
          </two>
        </my-component>
      </div>
  <div>
        <my-component>
          <one :slot="one">
            A
          </one>
          <two :slot="two">
            B
          </two>
        </my-component>
      </div>
</template>

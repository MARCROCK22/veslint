<template>
  <div><button @click="foo"/></div>
  <div><button @click="foo" :click="foo"/></div>
  <div><button @click.ctrl="foo"/></div>
  <div><button @click.exact="foo"/></div>
  <div><button v-on:click="foo"/></div>
  <div><button v-on:click.ctrl="foo"/></div>
  <div><button v-on:click.exact="foo"/></div>
  <div><button @click="foo" @click.stop="bar"/></div>
  <div><button @click="foo" @click.prevent="bar" @click.stop="baz"/></div>
  <div><button @click.prevent="foo" @click.stop="bar"/></div>
  <div><button @click.exact="foo" @click.ctrl="bar"/></div>
  <div><button @click.exact="foo" @click.ctrl.exact="bar" @click.ctrl.shift="baz"/></div>
  <div><button @click.ctrl.exact="foo" @click.ctrl.shift="bar"/></div>
  <div><button @click.exact="foo" @click.ctrl="foo"/></div>
  <div><button @click="foo" @focus="foo"/></div>
  <div><button @click="foo" @click="foo"/></div>
  <div><button @click="foo"/><button @click.ctrl="foo"/></div>
  <div><button v-on:click.exact="foo" v-on:click.ctrl="foo"/></div>
  <div><a @mouseenter="showTooltip" @mouseenter.once="attachTooltip"/></div>
  <div><input @keypress.exact="foo" @keypress.esc.exact="bar" @keypress.ctrl="baz"></div>
  <div><input @keypress.a="foo" @keypress.b="bar" @keypress.a.b="baz"></div>
  <div><input @keypress.shift="foo" @keypress.ctrl="bar"></div>
  <div>
        <input
          @keypress.27="foo"
          @keypress.27.middle="bar"
        >
      </div>
  <div>
        <input
          @keydown.a.b.c="abc"
          @keydown.a="a"
          @keydown.b="b"
          @keydown.c="c"
        >
      </div>
  <div>
        <input
          @keydown.a.b="ab"
          @keydown.a="a"
          @keydown.b="b"
          @keydown.c="c"
          @keydown.a.c="ac"
        >
      </div>
  <div>
        <input
          @keydown.a.b="ab"
          @keydown.a="a"
          @keydown.b="b"
          @keydown.c="c"
        >
      </div>
  <div><UiButton @click="foo" /></div>
  <div><UiButton @click="foo" @click.native="bar" /></div>
  <div><UiButton @click="foo" @click.native.ctrl="bar" /></div>
  <div><UiButton @click="foo" @click.native.exact="bar" @click.native.ctrl="baz" /></div>
  <div><UiButton @click.native.exact="bar" @click.ctrl.native="baz" /></div>
  <div><UiButton @click.native.ctrl.exact="foo" @click.native.ctrl.shift="bar" /></div>
  <div><UiButton @click.native="foo" @click.native.stop="bar" /></div>
  <div><UiButton @click.native.stop="foo" @click.native.prevent="bar" /></div>
  <div><button @[click]="foo"/></div>
  <div><button @[foo]="foo" @[bar].ctrl="bar"/></div>
  <div>
        <input
          @keydown.enter="foo"
          @keydown.shift.tab="bar"/>
      </div>
  <div>
        <input
          @keydown.enter="foo"
          @keydown.shift.tab.prevent="bar"/>
      </div>
  <div>
        <input
          @keydown.ctrl.enter.exact="save"
          @keydown.stop
        />
      </div>
  <div>
        <input-component
          @keydown.enter.native="foo"
          @keydown.shift.tab.native="bar"/>
      </div>
  <div>
        <button
          @click="foo"
          @click.ctrl="bar"
        />
      </div>
  <div>
        <button
          @click="foo"
          @click.ctrl.stop="bar"
        />
      </div>
  <div>
        <button
          @click.prevent="foo"
          @click.ctrl="bar"
        />
      </div>
  <div>
        <input
          @keydown.prevent="foo"
          @keydown.ctrl="bar"
        />
      </div>
  <div>
        <input
          @keydown.ctrl.enter.exact="save"
          @keydown.stop="foo"
        />
      </div>
  <div>
        <button
          @click.exact="foo"
          @click.ctrl="bar"
          @click.ctrl.shift="baz"
        />
      </div>
  <div>
        <button
          @click="foo"
          @click.ctrl="bar"
          @click.ctrl.shift="baz"
        />
      </div>
  <div>
        <input
          @keypress.27="foo"
          @keypress.27.shift="bar"
        >
      </div>
  <div>
        <input
          @keypress.exact="foo"
          @keypress.esc="bar"
          @keypress.ctrl="baz"
        >
      </div>
  <div>
        <UiButton
          @click="foo"
          @click.native="bar"
          @click.ctrl.native="baz"
        />
      </div>
  <div>
        <UiButton
          @click.native.ctrl="foo"
          @click.native.ctrl.shift="bar"
        />
      </div>
  <div>
        <UiButton
          @click.native="foo"
          @click.native.ctrl="bar"
          @click.native.ctrl.shift="baz"
        />
      </div>
  <div>
        <button
          @[foo]="foo"
          @[foo].ctrl="bar"
        />
      </div>
</template>

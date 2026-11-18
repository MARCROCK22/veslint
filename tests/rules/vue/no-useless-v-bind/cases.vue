<template>
  <div>
      <div id="foo" />
      <div id='foo' />
      <div id=foo />
      <div :id="foo" />
      <div :id="'foo' || 'bar'" />
      <div :id="1" />
      <div :id />
      <div :id="{" />
      <div :id="null" />
    </div>
  <div>
        <div :id="'foo'" />
        <div v-bind:id="'foo'" />
      </div>
  <div>
        <div :id="'comment'/*comment*/" />
        <div :id="'comment'//comment
        " />
      </div>
  <div>
        <div :id="'\n'" />
        <div :id="'\r'" />
      </div>
  <div>
        <div :id="'&quot;'" />
        <div :id=`&quot;&apos;` />
        <div :id="'\\'" />
        <div :id="'\\r'" />
        <div :id="'\'" />
        <div :id="`foo`" />
        <div :id="`foo${bar}`" />
        <div :id='"&apos;"' />
        <div :id=`foo` />
      </div>
  <div>
        <div :id="    'foo'    " />
        <div :id='    "foo"    ' />
        <div :id="   `foo`   " />
        <div :id='   `foo`   ' />
        <div :id="' \'foo\' '" />
        <div :id='" \"foo\" "' />
      </div>
</template>

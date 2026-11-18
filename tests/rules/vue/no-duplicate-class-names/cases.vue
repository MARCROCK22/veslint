<template>
  <div><div></div></div>
  <div><div class="foo"></div></div>
  <div><div class="foo bar baz"></div></div>
  <div><div :class="'foo bar baz'"></div></div>
  <div><div :class="`foo bar baz`"></div></div>
  <div><div :class="{ 'foo bar baz': true }"></div></div>
  <div><div :class="{ 'foo': true, 'foo bar': true }"></div></div>
  <div><div :class="isActive ? 'foo' : 'bar'"></div></div>
  <div><div :class="isActive ? 'foo' : 'foo'"></div></div>
  <div><div :class="[isActive1 && { 'foo': isActive2, 'bar': isActive3 }, isActive4 && 'bar']"></div></div>
  <div><div :class="[isActive1 && 'foo', isActive2 && 'foo']"></div></div>
  <div><div :class="[isActive1 && ('foo' + ' bar'), isActive2 && 'foo']"></div></div>
  <div><div class="foo foo"></div></div>
  <div><div class="foo bar foo baz bar"></div></div>
  <div><div :class="'foo foo'"></div></div>
  <div><div :class="`foo foo`"></div></div>
  <div><div :class="{ 'foo foo': true }"></div></div>
  <div><div :class="{ 'foo foo bar': true, 'bar bar baz': true }"></div></div>
  <div><div :class="['foo foo']"></div></div>
  <div><div :class="['foo foo', 'bar bar baz']"></div></div>
  <div><div :class="['foo foo', { 'bar bar baz': true }]"></div></div>
  <div><div :class="isActive ? 'foo foo' : 'bar'"></div></div>
  <div><div :class="'foo foo ' + ' bar'"></div></div>
  <div><div class="foo foo     bar"></div></div>
  <div><div class="foo bar    baz foo"></div></div>
  <div><div class="foo bar foo     baz"></div></div>
  <div><div class="foo" :class="'foo'"></div></div>
  <div><div class="foo" :class="`foo`"></div></div>
  <div><div class="foo" :class="'foo bar'"></div></div>
  <div><div class="foo bar" :class="'foo bar'"></div></div>
  <div><div class="foo" :class="['foo', 'bar']"></div></div>
  <div><div class="foo" :class="{ 'foo': true }"></div></div>
  <div><div class="foo" :class="['foo', { 'bar': true }]"></div></div>
  <div><div class="foo" :class="'foo ' + 'bar'"></div></div>
  <div><div class="foo" :class="isActive ? 'foo' : 'bar'"></div></div>
  <div><div :class="['foo', 'foo']"></div></div>
  <div><div :class="'foo ' + 'foo'"></div></div>
  <div><div :class="['foo', { 'foo': true }]"></div></div>
  <div><div :class="isActive && 'foo foo'"></div></div>
  <div><div :class="isActive || 'foo foo'"></div></div>
  <div><div :class="isActive ?? 'foo foo'"></div></div>
  <div><div :class="isActive ?? isAnotherActive ?? 'foo foo'"></div></div>
  <div><div :class="['foo', isActive ?? 'bar bar']"></div></div>
  <div><div :class="isAnotherActive ? isActive ?? 'foo foo' : 'bar'"></div></div>
  <div><div :class="isActive && 'bar' + ' bar'"></div></div>
  <div><div :class="isActive && `foo ${bar} foo`"></div></div>
</template>

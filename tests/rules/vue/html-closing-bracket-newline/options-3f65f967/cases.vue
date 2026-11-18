<template>
  <div>
          <MyComp :foo="foo"
          />
          <MyComp
            :foo="foo" />
        </div>
  <div>
          <MyComp :foo="foo"/>
        </div>
  <div>
          <MyComp
            :foo="foo"
          />
        </div>
</template>

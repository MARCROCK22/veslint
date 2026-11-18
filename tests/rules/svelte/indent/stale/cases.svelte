<script lang="ts">
  enum Color {
    Red,
      Green,
    Blue = 1
  }
  type M<T> = {
    [K in keyof T]: T[K]
  };
  let x: M<{ a: Color }> = { a: Color.Red };
</script>

<div class="c1">
  <span>
      {x.a}
  </span>
</div>
<div class="c2">
  <span>
      {x.a}
  </span>
</div>
<div class="c3">
  <span>
      {x.a}
  </span>
</div>
<div class="c4">
  <span>
      {x.a}
  </span>
</div>
<div class="c5">
  <span>
      {x.a}
  </span>
</div>
<div class="c6">
  <span>
      {x.a}
  </span>
</div>
<div class="c7">
  <span>
      {x.a}
  </span>
</div>
<div class="c8">
  <span>
      {x.a}
  </span>
</div>
<div class="c9">
  <span>
      {x.a}
  </span>
</div>
<div class="c10">
  <span>
      {x.a}
  </span>
</div>
<div class="c11">
  <span>
      {x.a}
  </span>
</div>
<div class="c12">
  <span>
      {x.a}
  </span>
</div>
<div class="c13">
  <span>
      {x.a}
  </span>
</div>
<div class="c14">
  <span>
      {x.a}
  </span>
</div>
<div class="c15">
  <span>
      {x.a}
  </span>
</div>
<div class="c16">
  <span>
      {x.a}
  </span>
</div>
<div class="c17">
  <span>
      {x.a}
  </span>
</div>
<div class="c18">
  <span>
      {x.a}
  </span>
</div>
<div class="c19">
  <span>
      {x.a}
  </span>
</div>
<div class="c20">
  <span>
      {x.a}
  </span>
</div>
<div class="c21">
  <span>
      {x.a}
  </span>
</div>
<div class="c22">
  <span>
      {x.a}
  </span>
</div>
<div class="c23">
  <span>
      {x.a}
  </span>
</div>
<div class="c24">
  <span>
      {x.a}
  </span>
</div>
<div class="c25">
  <span>
      {x.a}
  </span>
</div>
<div class="c26">
  <span>
      {x.a}
  </span>
</div>
<div class="c27">
  <span>
      {x.a}
  </span>
</div>
<div class="c28">
  <span>
      {x.a}
  </span>
</div>
<div class="c29">
  <span>
      {x.a}
  </span>
</div>
<div class="c30">
  <span>
      {x.a}
  </span>
</div>

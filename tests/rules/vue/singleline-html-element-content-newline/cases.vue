<template>
  <div>
        <slot name="panel"></slot>
      </div>
  <div>
        <div class="panel">
          content
        </div>
      </div>
  <div>
        <div class="panel">
          <div>
          </div>
        </div>
      </div>
  <div>
        <div class="panel">
          <!-- comment -->
        </div>
      </div>
  <div>
        <div>
          content
        </div>
      </div>
  <div>
        <div>
          <div>
          </div>
        </div>
      </div>
  <div>
        <div>
          <!-- comment -->
        </div>
      </div>
  <div>
        <a href="/">Home</a>
      </div>
  <div>
        <form>
          <label for="test">Home</label>
          <input id="test" name="test">
        </form>
      </div>
  <div>
        <router-link to="/">Home</router-link>
        <RouterLink to="/">Home</RouterLink>
        <nuxt-link to="/">Home</nuxt-link>
        <NuxtLink to="/">Home</NuxtLink>
      </div>
  <div>
        <div>singleline content</div>
      </div>
  <div>
        <tr><td>singleline</td><td>children</td></tr>
      </div>
  <div>
        <div><!-- singleline comment --></div>
      </div>
  <div>
        <div     >singleline element</div     >
      </div>
  <div>
        <div></div>
      </div>
  <div>
        <div>    </div>
      </div>
  <div>
        <self-closing />
      </div>
  <div>
        <pre>content</pre>
        <pre attr>content</pre>
        <pre><span attr>content</span></pre>
        <textarea>content</textarea>
        <textarea attr>content</textarea>
        <textarea><span attr>content</span></textarea>
      </div>
  <div>
        <div>content
        </div>
      </div>
  <div>
        <div>
          content</div>
      </div>
  <div>
          <div class="panel">content</div>
        </div>
  <div>
          <tr attr><td>singleline</td><td>children</td></tr>
        </div>
  <div>
          <div attr><!-- singleline comment --></div>
        </div>
  <div>
          <div attr><!-- singleline --><!-- comments --></div>
        </div>
  <div>
          <div attr     >content</div    >
        </div>
  <div>
          <div attr     >content</div
          >
        </div>
  <div>
          <div attr>    </div>
        </div>
  <div>
          <Div class="panel">content</Div>
        </div>
</template>

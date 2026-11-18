<script lang="ts">
export default {
  props: {
    greetingText: String,
    greeting_text: String,
    'greeting-text': String,
    GreetingText: String,
    ['computed_key']: String,
    [dynamic]: String,
    '': String,
    _private: String,
  },
}
declare const dynamic: string
</script>

<script setup lang="ts">
function validate(v: unknown) {
  return !!v
}
defineEmits({ a: { type: String, validator: validate } })
</script>

<script setup lang="ts">
function validate(v: unknown) {
  return !!v
}
defineProps({ a: { type: String, validator: validate } })
</script>

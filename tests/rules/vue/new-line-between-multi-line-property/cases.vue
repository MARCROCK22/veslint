<script lang="ts">
export default {
  props: {
    value: {
      type: String,
      required: true,
    },
    focused: {
      type: Boolean,
      default: false,
    }, // trailing
    label: String,
  },
  data() {
    return {
      a: 1,
    }
  },
  computed: {
    foo() {
      return defineX({
        x: {
          a: 1,
        },
        y: 2,
      })
    },
  },
  methods: {},
}
declare function defineX(o: object): object
</script>

// unicorn/prefer-export-from: removed declarations leave a `;` after code without one.
let counter = 1
import value from 'value-module'
counter++
export {value}
counter--
const label = 'x'
export default value
const after = 2
import single from 'single-module'
export {single}
let tail = [after]
import * as ns from 'ns-module'
export {ns}

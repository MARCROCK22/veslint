module rules

import collation

// js_locale_compare is `Math.sign(a.localeCompare(b))` of Node (ICU's root collation, which the
// en-US locale uses): collation.compare.
fn js_locale_compare(a string, b string) int {
	return collation.compare(a, b)
}

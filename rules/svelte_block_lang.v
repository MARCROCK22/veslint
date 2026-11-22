module rules

import json2

// Port of the `svelte/block-lang` rule of eslint-plugin-svelte 3.24.1: the `lang` of the <script>
// and <style> blocks of a component must be one of those the options allow (script, style: a
// lang, null for none, or a list; null by default), and with enforceScriptPresent /
// enforceStylePresent the block must be there. Reports with messages of their own and
// suggestions (add the block, set or remove the lang attribute).

const sbl_messages = map[string]string{}

// SblLang is an allowed lang: a name, or null (no lang attribute).
struct SblLang {
	null bool
	name string
}

struct SblOptions {
	enforce_script bool
	enforce_style  bool
	script         []SblLang
	style          []SblLang
}

fn sbl_lang(item json2.Any) SblLang {
	return if item is string {
		SblLang{
			name: item
		}
	} else {
		SblLang{
			null: true
		}
	}
}

// sbl_langs reads the `script` or `style` option of the options object: a lang, null, or a list
// of them; null when it is not there.
fn sbl_langs(values map[string]json2.Any, key string) []SblLang {
	v := values[key] or {
		return [SblLang{
			null: true
		}]
	}
	if v is []json2.Any {
		return v.map(sbl_lang(it))
	}
	return [sbl_lang(v)]
}

fn sbl_options(options []json2.Any) !SblOptions {
	o := option_object(svelte_block_lang, options, ['enforceScriptPresent', 'enforceStylePresent',
		'script', 'style'])!
	return SblOptions{
		enforce_script: o.bool_value('enforceScriptPresent')!
		enforce_style:  o.bool_value('enforceStylePresent')!
		script:         sbl_langs(o.values, 'script')
		style:          sbl_langs(o.values, 'style')
	}
}

fn sbl_has_null(langs []SblLang) bool {
	return langs.any(it.null)
}

// sbl_named are the langs that are not null nor '' (filteredLangs).
fn sbl_named(langs []SblLang) []string {
	return langs.filter(!it.null && it.name != '').map(it.name)
}

// sbl_pretty is prettyPrintLangs.
fn sbl_pretty(langs []SblLang) string {
	quoted := langs.filter(!it.null).map('"${it.name}"')
	if quoted.len == 0 {
		return 'omitted'
	}
	prefix := if sbl_has_null(langs) { 'either omitted or ' } else { '' }
	return prefix + if quoted.len == 1 { quoted[0] } else { 'one of ${quoted.join(', ')}' }
}

// sbl_allows: the lang (none for no static lang) is allowed.
fn sbl_allows(langs []SblLang, lang ?string) bool {
	if l := lang {
		return langs.any(!it.null && it.name == l)
	}
	return sbl_has_null(langs)
}

// sbl_add_suggestions is buildAddLangSuggestions.
fn (c &Checker) sbl_add_suggestions(langs []SblLang, tag string) []Suggestion {
	at := if tag == 'script' { 0 } else { c.svelte.doc.src.len }
	return sbl_named(langs).map(Suggestion{
		desc: 'Add a lang attribute to a <${tag}> block with the value "${it}".'
		fix:  Fix{
			start: at
			end:   at
			text:  '<${tag} lang="${it}">\n</${tag}>\n\n'
		}
	})
}

// sbl_replace_suggestions is buildReplaceLangSuggestions.
fn (c &Checker) sbl_replace_suggestions(langs []SblLang, element int) []Suggestion {
	doc := c.svelte.doc
	tag := c.sv_element_name(element)
	attr := c.sv_find_attribute(element, 'lang')
	named := sbl_named(langs)
	if named.len == 0 && sbl_has_null(langs) && attr >= 0 {
		return [
			Suggestion{
				desc: 'Replace a <${tag}> block with the lang attribute omitted.'
				fix:  Fix{
					start: doc.nodes[attr].start - 1
					end:   doc.nodes[attr].end
				}
			},
		]
	}
	start_tag := doc.nodes[doc.nodes[element].start_tag]
	return named.map(fn [c, doc, attr, tag, start_tag] (lang string) Suggestion {
		if attr >= 0 {
			return Suggestion{
				desc: 'Replace a <${tag}> block with the lang attribute set to "${lang}".'
				fix:  Fix{
					start: doc.nodes[attr].start
					end:   doc.nodes[attr].end
					text:  'lang="${lang}"'
				}
			}
		}
		at := start_tag.start + tag.len + 1
		return Suggestion{
			desc: 'Add lang attribute to a <${tag}> block with the value "${lang}".'
			fix:  Fix{
				start: at
				end:   at
				text:  ' lang="${lang}"'
			}
		}
	})
}

// sbl_at_start is a report at `{ line: 1, column: 1 }` (ESLint's column 2), without an end.
fn (c &Checker) sbl_at_start(message string, suggestions []Suggestion) Finding {
	src := c.svelte.doc.src
	// The second character of the first line, for the order of the findings.
	start := if src.len > 0 && src[0] != `\n` && src[0] != `\r` { 1 } else { 0 }
	return Finding{
		stmt:         c.position_range(start, start)
		text:         message
		fixed_line:   1
		fixed_column: 2
		no_end:       true
		suggestions:  suggestions
	}
}

fn (mut c Checker) lint_svelte_block_lang(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	options := sbl_options(c.rule_options(svelte_block_lang))!
	if !c.is_svelte() {
		return []
	}
	scripts := c.sv_snodes_of(.script_element)
	styles := c.sv_snodes_of(.style_element)
	mut findings := []Finding{}
	if scripts.len == 0 && options.enforce_script {
		findings << c.sbl_at_start('The <script> block should be present and its lang attribute should be ${sbl_pretty(options.script)}.',
			c.sbl_add_suggestions(options.script, 'script'))
	}
	for s in scripts {
		lang := if l := c.sv_lang_value(s) { ?string(vue_js_to_lower(l)) } else { ?string(none) }
		if !sbl_allows(options.script, lang) {
			n := c.svelte.doc.nodes[s]
			findings << Finding{
				...c.sv_report_message(n.start, c.sv_snode_loc_end(s), 'The lang attribute of the <script> block should be ${sbl_pretty(options.script)}.')
				suggestions: c.sbl_replace_suggestions(options.script, s)
			}
		}
	}
	if styles.len == 0 && options.enforce_style {
		findings << c.sbl_at_start('The <style> block should be present and its lang attribute should be ${sbl_pretty(options.style)}.',
			c.sbl_add_suggestions(options.style, 'style'))
	}
	for s in styles {
		lang := if l := c.sv_lang_value(s) { ?string(vue_js_to_lower(l)) } else { ?string(none) }
		if !sbl_allows(options.style, lang) {
			n := c.svelte.doc.nodes[s]
			findings << Finding{
				...c.sv_report_message(n.start, c.sv_snode_loc_end(s), 'The lang attribute of the <style> block should be ${sbl_pretty(options.style)}.')
				suggestions: c.sbl_replace_suggestions(options.style, s)
			}
		}
	}
	return findings
}

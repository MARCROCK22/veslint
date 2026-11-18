module rules

import json2
import time

// Port of the `vue/block-lang` rule of eslint-plugin-vue 10.12.1 (option: by block name, `lang`
// (a name or a list), `allowNoLang`, `required`; by default script, template and style may go
// without `lang`): the `lang` attribute of each top-level block that is not one of the allowed
// languages, or missing where it must be given, and a required block that is missing (at 1:1).

const vblang_messages = {
	'expected':          "Only {{allows}} can be used for the 'lang' attribute of '<{{tag}}>'."
	'missing':           "The 'lang' attribute of '<{{tag}}>' is missing."
	'missingBlock':      "The '<{{tag}}>' block is missing."
	'unexpected':        "Do not specify the 'lang' attribute of '<{{tag}}>'."
	'useOrNot':          "Only {{allows}} can be used for the 'lang' attribute of '<{{tag}}>'. Or, not specifying the 'lang' attribute is allowed."
	'unexpectedDefault': "Do not explicitly specify the default language for the 'lang' attribute of '<{{tag}}>'."
}

struct VblangBlock {
	name          string
	lang          []string
	allow_no_lang bool
	required      bool
}

fn vblang_defaults(block string) []string {
	return match block {
		'template' { ['html'] }
		'style' { ['css'] }
		'script' { ['js', 'javascript'] }
		else { []string{} }
	}
}

fn vblang_options(options []json2.Any) ![]VblangBlock {
	mut written := map[string]json2.Any{}
	if options.len > 0 && options[0] is map[string]json2.Any {
		written = options[0].as_map()
	} else if options.len > 0 {
		return error('the option of `${vue_block_lang}` must be an object')
	} else {
		for name in ['script', 'template', 'style'] {
			written[name] = json2.Any({
				'allowNoLang': json2.Any(true)
			})
		}
	}
	mut out := []VblangBlock{}
	for name, value in written {
		if value !is map[string]json2.Any {
			return error('the options of block `${name}` of `${vue_block_lang}` must be an object')
		}
		o := option_object(vue_block_lang, [value], ['lang', 'allowNoLang', 'required'])!
		mut lang := []string{}
		if l := o.values['lang'] {
			if l is string {
				lang << l
			} else if l is []json2.Any {
				for item in l {
					if item !is string {
						return error('`lang` of `${vue_block_lang}` must be texts')
					}
					s := item as string
					if s !in lang {
						lang << s
					}
				}
			} else {
				return error('`lang` of `${vue_block_lang}` must be a text or a list of texts')
			}
		}
		defaults := vblang_defaults(name)
		has_default := lang.any(it in defaults)
		lang = lang.filter(it !in defaults)
		required_value := o.values['required'] or { json2.Any(false) }
		required := required_value is bool && required_value as bool
		out << VblangBlock{
			name:          name
			lang:          lang
			allow_no_lang: lang.len == 0 || has_default || o.bool_value('allowNoLang')!
			required:      required
		}
	}
	return out
}

// vblang_allows is getAllowsLangPhrase.
fn vblang_allows(lang []string) string {
	langs := lang.map("'${it}'")
	if langs.len == 1 {
		return langs[0]
	}
	if langs.len == 0 {
		return ', and undefined'
	}
	return '${langs[..langs.len - 1].join(', ')}, and ${langs.last()}'
}

fn (mut c Checker) lint_vue_block_lang(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	blocks := vblang_options(c.rule_options(vue_block_lang))!
	mut findings := []Finding{}
	if blocks.len == 0 {
		return findings
	}
	doc := c.vue.doc
	mut existing := map[string]bool{}
	for element in doc.nodes[0].children {
		el := doc.nodes[element]
		if el.typ != .v_element {
			continue
		}
		existing[el.name] = true
		stats.checked++
		option := blocks.filter(it.name == el.name)
		if option.len == 0 {
			continue
		}
		o := option[0]
		lang := c.vue_get_attribute(element, 'lang', none)
		if lang < 0 || doc.nodes[lang].value < 0 {
			if !o.allow_no_lang {
				findings << c.vue_report_vnode(el.start_tag, 'missing', {
					'tag': el.name
				})
			}
			continue
		}
		value := doc.nodes[doc.nodes[lang].value].text
		if value in o.lang {
			continue
		}
		message_id := if !o.allow_no_lang {
			'expected'
		} else if o.lang.len == 0 {
			if value in vblang_defaults(el.name) { 'unexpectedDefault' } else { 'unexpected' }
		} else {
			'useOrNot'
		}
		findings << c.vue_report_vnode(lang, message_id, {
			'tag':    el.name
			'allows': vblang_allows(o.lang)
		})
	}
	for o in blocks {
		if !o.required || o.name in existing {
			continue
		}
		findings << Finding{
			stmt:         c.position_at(0)
			message_id:   'missingBlock'
			data:         {
				'tag': o.name
			}
			fixed_line:   1
			fixed_column: 1
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

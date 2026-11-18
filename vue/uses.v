module vue

// What vue-eslint-parser's analyzeUsedInTemplateVariables (src/script-setup/scope-analyzer.ts)
// reads from the template of a file with a <script setup> to mark the variables of the script the
// template uses: a linter applies the marks to its scope tree (rules/vue_scope.v).

// UseKind is how a TemplateUse names a variable: `exact` is markVariableAsUsed (the name as it
// is), `component` markSetupReferenceVariableAsUsed (the name, its camelCase or its PascalCase,
// and for an element, the part before a `.` when none of those is a variable).
pub enum UseKind {
	exact
	component
	element
}

// TemplateUse is a use of a script variable by the template, in the order of the traversal.
// `has_kind` is false for a name that is not a reference (an element, a directive, a `ref`), whose
// reference has no isValueReference/isTypeReference.
pub struct TemplateUse {
pub:
	kind               UseKind
	name               string
	is_value_reference bool
	is_type_reference  bool
	has_kind           bool
}

const builtin_components = ['template', 'slot', 'component', 'Component', 'transition', 'Transition',
	'transition-group', 'TransitionGroup', 'keep-alive', 'KeepAlive', 'teleport', 'Teleport', 'suspense',
	'Suspense']

const builtin_directives = ['bind', 'on', 'text', 'html', 'show', 'if', 'else', 'else-if', 'for',
	'model', 'slot', 'pre', 'cloak', 'once', 'memo', 'is']

// native_tags are the HTML and SVG tags of @vue/shared's domTagConfig (vue-eslint-parser's
// NATIVE_TAGS).
const native_tags = 'html,body,base,head,link,meta,style,title,address,article,aside,footer,header,h1,h2,h3,h4,h5,h6,nav,section,div,dd,dl,dt,figcaption,figure,picture,hr,img,li,main,ol,p,pre,ul,a,b,abbr,bdi,bdo,br,cite,code,data,dfn,em,i,kbd,mark,q,rp,rt,ruby,s,samp,small,span,strong,sub,sup,time,u,var,wbr,area,audio,map,track,video,embed,object,param,source,canvas,script,noscript,del,ins,caption,col,colgroup,table,thead,tbody,td,th,tr,button,datalist,fieldset,form,input,label,legend,meter,optgroup,option,output,progress,select,textarea,details,dialog,menu,summary,template,blockquote,iframe,tfoot,svg,animate,animateMotion,animateTransform,circle,clipPath,color-profile,defs,desc,discard,ellipse,feBlend,feColorMatrix,feComponentTransfer,feComposite,feConvolveMatrix,feDiffuseLighting,feDisplacementMap,feDistanceLight,feDropShadow,feFlood,feFuncA,feFuncB,feFuncG,feFuncR,feGaussianBlur,feImage,feMerge,feMergeNode,feMorphology,feOffset,fePointLight,feSpecularLighting,feSpotLight,feTile,feTurbulence,filter,foreignObject,g,hatch,hatchpath,image,line,linearGradient,marker,mask,mesh,meshgradient,meshpatch,meshrow,metadata,mpath,path,pattern,polygon,polyline,radialGradient,rect,set,solidcolor,stop,switch,symbol,text,textPath,title,tspan,unknown,use,view'.split(',')

// has_script_setup: a top-level <script> is a <script setup> (vue-eslint-parser only analyzes
// the scope of such a file).
pub fn (d &Document) has_script_setup() bool {
	return d.top_elements('script').any(d.is_script_setup(it))
}

// script_setup_block is the file range of the content of the <script setup> when vue-eslint-parser
// wraps it in a block statement (parseScriptSetupElements: the file has two top-level scripts and
// the setup one has content); (-1, -1) otherwise.
pub fn (d &Document) script_setup_block() (int, int) {
	scripts := d.top_elements('script')
	if scripts.len != 2 {
		return -1, -1
	}
	for s in scripts {
		if d.is_script_setup(s) {
			text := d.text_child(s)
			if text < 0 {
				return -1, -1
			}
			return d.nodes[text].start, d.nodes[text].end
		}
	}
	return -1, -1
}

// script_setup_generic_names are the names a `generic` of the <script setup> defines.
pub fn (d &Document) script_setup_generic_names() []string {
	for s in d.top_elements('script') {
		if !d.is_script_setup(s) {
			continue
		}
		if d.generic_container(s) < 0 {
			return []string{}
		}
		return d.nodes[s].variables.filter(d.variables[it].kind == 'generic').map(d.variables[it].name)
	}
	return []string{}
}

// generic_container is the VExpressionContainer of the `generic` directive of a script, or -1.
fn (d &Document) generic_container(script int) int {
	for a in d.nodes[d.nodes[script].start_tag].attributes {
		attr := d.nodes[a]
		if attr.directive && attr.key >= 0 && d.directive_name(attr.key) == 'generic' {
			return attr.value
		}
	}
	return -1
}

// directive_name is `key.name.name` of a VDirectiveKey.
fn (d &Document) directive_name(key int) string {
	dir_name := d.nodes[key].dir_name
	return if dir_name >= 0 { d.nodes[dir_name].name } else { '' }
}

// template_uses lists, in vue-eslint-parser's order, what marks script variables as used.
pub fn (d &Document) template_uses() []TemplateUse {
	mut uses := []TemplateUse{}
	if d.template_body >= 0 {
		d.collect_uses(d.template_body, mut uses)
	}
	for child in d.nodes[0].children {
		node := d.nodes[child]
		if node.typ != .v_element {
			continue
		}
		if node.name == 'script' && d.is_script_setup(child) {
			container := d.generic_container(child)
			if container >= 0 {
				d.container_uses(container, mut uses)
			}
		} else if node.name == 'style' {
			for c in node.children {
				if d.nodes[c].typ == .v_expression_container {
					d.container_uses(c, mut uses)
				}
			}
		}
	}
	return uses
}

// collect_uses walks a node of the template with vue-eslint-parser's keys (VElement: startTag,
// children; VStartTag: attributes; VAttribute: key, value; VDirectiveKey: argument).
fn (d &Document) collect_uses(n int, mut uses []TemplateUse) {
	if n < 0 {
		return
	}
	node := d.nodes[n]
	match node.typ {
		.v_element {
			if !((node.raw_name == node.name && node.raw_name in native_tags)
				|| node.raw_name in builtin_components) {
				uses << TemplateUse{
					kind: .element
					name: node.raw_name
				}
			}
			d.collect_uses(node.start_tag, mut uses)
			for c in node.children {
				d.collect_uses(c, mut uses)
			}
		}
		.v_start_tag {
			for a in node.attributes {
				d.collect_uses(a, mut uses)
			}
		}
		.v_attribute {
			if node.directive {
				if node.key >= 0 {
					name := d.directive_name(node.key)
					if name !in builtin_directives {
						dir_name := d.nodes[node.key].dir_name
						uses << TemplateUse{
							kind: .component
							name: 'v-${d.nodes[dir_name].raw_name}'
						}
					}
					d.collect_uses(d.nodes[node.key].argument, mut uses)
				}
			} else if node.key >= 0 && d.nodes[node.key].name == 'ref' && node.value >= 0 {
				uses << TemplateUse{
					kind: .exact
					name: d.nodes[node.value].text
				}
			}
			d.collect_uses(node.value, mut uses)
		}
		.v_expression_container {
			d.container_uses(n, mut uses)
		}
		else {}
	}
}

// container_uses are the references of a VExpressionContainer that resolve to nothing in the
// template.
fn (d &Document) container_uses(container int, mut uses []TemplateUse) {
	for r in d.nodes[container].references {
		ref := d.references[r]
		if ref.variable >= 0 {
			continue
		}
		uses << TemplateUse{
			kind:               .exact
			name:               ref.name
			is_value_reference: ref.is_value_reference
			is_type_reference:  ref.is_type_reference
			has_kind:           ref.has_kind
		}
	}
}

// camelized is vue-eslint-parser's camelize (/-(\w)/g to upper case).
pub fn camelized(s string) string {
	return camelize(s)
}

module rules

import estree
import time

// Port of the `vue/prefer-import-from-vue` rule of eslint-plugin-vue 10.12.1 (no options): an
// import or export from '@vue/runtime-dom', '@vue/runtime-core', '@vue/reactivity' or
// '@vue/shared' (unless none of its names is one 'vue' exports), with the fix that imports from
// 'vue' when every name it takes is one 'vue' exports.

const vue_prefer_import_from_vue_messages = {
	'importedAtVue': "Import from 'vue' instead of '{{source}}'."
}

const vpifv_target_modules = ['@vue/runtime-dom', '@vue/runtime-core', '@vue/reactivity', '@vue/shared']

// lib/utils/vue3-export-names.json: the names 'vue' exports.
const vpifv_vue3_export_names = {
	'ComputedGetter':                          true
	'ComputedRef':                             true
	'ComputedSetter':                          true
	'CustomRefFactory':                        true
	'DebuggerEvent':                           true
	'DebuggerEventExtraInfo':                  true
	'DebuggerOptions':                         true
	'DeepReadonly':                            true
	'EffectScheduler':                         true
	'EffectScope':                             true
	'MaybeRef':                                true
	'MaybeRefOrGetter':                        true
	'Raw':                                     true
	'Reactive':                                true
	'ReactiveEffect':                          true
	'ReactiveEffectOptions':                   true
	'ReactiveEffectRunner':                    true
	'ReactiveFlags':                           true
	'Ref':                                     true
	'ShallowReactive':                         true
	'ShallowRef':                              true
	'ShallowUnwrapRef':                        true
	'ToRef':                                   true
	'ToRefs':                                  true
	'TrackOpTypes':                            true
	'TriggerOpTypes':                          true
	'UnwrapNestedRefs':                        true
	'UnwrapRef':                               true
	'WatchCallback':                           true
	'WatchEffect':                             true
	'WatchHandle':                             true
	'WatchSource':                             true
	'WatchStopHandle':                         true
	'WritableComputedOptions':                 true
	'WritableComputedRef':                     true
	'customRef':                               true
	'effect':                                  true
	'effectScope':                             true
	'getCurrentScope':                         true
	'getCurrentWatcher':                       true
	'isProxy':                                 true
	'isReactive':                              true
	'isReadonly':                              true
	'isRef':                                   true
	'isShallow':                               true
	'markRaw':                                 true
	'onScopeDispose':                          true
	'onWatcherCleanup':                        true
	'proxyRefs':                               true
	'reactive':                                true
	'readonly':                                true
	'ref':                                     true
	'shallowReactive':                         true
	'shallowReadonly':                         true
	'shallowRef':                              true
	'stop':                                    true
	'toRaw':                                   true
	'toRef':                                   true
	'toRefs':                                  true
	'toValue':                                 true
	'triggerRef':                              true
	'unref':                                   true
	'camelize':                                true
	'capitalize':                              true
	'normalizeClass':                          true
	'normalizeProps':                          true
	'normalizeStyle':                          true
	'toDisplayString':                         true
	'toHandlerKey':                            true
	'computed':                                true
	'Slot':                                    true
	'Slots':                                   true
	'SlotsType':                               true
	'nextTick':                                true
	'queuePostFlushCb':                        true
	'ComponentPropsOptions':                   true
	'ComponentObjectPropsOptions':             true
	'Prop':                                    true
	'PropType':                                true
	'ExtractPropTypes':                        true
	'ExtractPublicPropTypes':                  true
	'ExtractDefaultPropTypes':                 true
	'defineProps':                             true
	'DefineProps':                             true
	'defineEmits':                             true
	'ComponentTypeEmits':                      true
	'defineExpose':                            true
	'defineOptions':                           true
	'defineSlots':                             true
	'ModelRef':                                true
	'defineModel':                             true
	'withDefaults':                            true
	'useSlots':                                true
	'useAttrs':                                true
	'ObjectEmitsOptions':                      true
	'EmitsOptions':                            true
	'EmitsToProps':                            true
	'ShortEmitsToObject':                      true
	'EmitFn':                                  true
	'DirectiveBinding':                        true
	'DirectiveHook':                           true
	'ObjectDirective':                         true
	'FunctionDirective':                       true
	'Directive':                               true
	'DirectiveModifiers':                      true
	'DirectiveArguments':                      true
	'withDirectives':                          true
	'ComponentCustomProperties':               true
	'CreateComponentPublicInstance':           true
	'CreateComponentPublicInstanceWithMixins': true
	'ComponentPublicInstance':                 true
	'SuspenseProps':                           true
	'Suspense':                                true
	'SuspenseBoundary':                        true
	'RootHydrateFunction':                     true
	'BaseTransitionProps':                     true
	'TransitionHooks':                         true
	'TransitionState':                         true
	'useTransitionState':                      true
	'BaseTransitionPropsValidators':           true
	'BaseTransition':                          true
	'resolveTransitionHooks':                  true
	'setTransitionHooks':                      true
	'getTransitionRawChildren':                true
	'Renderer':                                true
	'HydrationRenderer':                       true
	'ElementNamespace':                        true
	'RootRenderFunction':                      true
	'RendererOptions':                         true
	'RendererNode':                            true
	'RendererElement':                         true
	'createRenderer':                          true
	'createHydrationRenderer':                 true
	'KeepAliveProps':                          true
	'KeepAlive':                               true
	'onActivated':                             true
	'onDeactivated':                           true
	'onBeforeMount':                           true
	'onMounted':                               true
	'onBeforeUpdate':                          true
	'onUpdated':                               true
	'onBeforeUnmount':                         true
	'onUnmounted':                             true
	'onServerPrefetch':                        true
	'onRenderTriggered':                       true
	'onRenderTracked':                         true
	'onErrorCaptured':                         true
	'ComponentCustomOptions':                  true
	'RenderFunction':                          true
	'ComponentOptionsBase':                    true
	'RuntimeCompilerOptions':                  true
	'ComponentOptions':                        true
	'ComponentOptionsMixin':                   true
	'ComputedOptions':                         true
	'MethodOptions':                           true
	'ComponentProvideOptions':                 true
	'ComponentInjectOptions':                  true
	'ComponentOptionsWithoutProps':            true
	'ComponentOptionsWithArrayProps':          true
	'ComponentOptionsWithObjectProps':         true
	'InjectionKey':                            true
	'provide':                                 true
	'inject':                                  true
	'hasInjectionContext':                     true
	'PublicProps':                             true
	'DefineComponent':                         true
	'DefineSetupFnComponent':                  true
	'defineComponent':                         true
	'App':                                     true
	'OptionMergeFunction':                     true
	'AppConfig':                               true
	'AppContext':                              true
	'ObjectPlugin':                            true
	'FunctionPlugin':                          true
	'Plugin':                                  true
	'CreateAppFunction':                       true
	'TeleportProps':                           true
	'Teleport':                                true
	'resolveComponent':                        true
	'resolveDynamicComponent':                 true
	'resolveDirective':                        true
	'Fragment':                                true
	'Text':                                    true
	'Comment':                                 true
	'Static':                                  true
	'VNodeTypes':                              true
	'VNodeRef':                                true
	'VNodeProps':                              true
	'VNodeArrayChildren':                      true
	'VNodeChild':                              true
	'VNodeNormalizedChildren':                 true
	'VNode':                                   true
	'openBlock':                               true
	'setBlockTracking':                        true
	'createElementBlock':                      true
	'createBlock':                             true
	'isVNode':                                 true
	'transformVNodeArgs':                      true
	'createBaseVNode':                         true
	'createVNode':                             true
	'guardReactiveProps':                      true
	'cloneVNode':                              true
	'createTextVNode':                         true
	'createStaticVNode':                       true
	'createCommentVNode':                      true
	'mergeProps':                              true
	'AllowedAttrs':                            true
	'Attrs':                                   true
	'ComponentInstance':                       true
	'ComponentCustomProps':                    true
	'GlobalDirectives':                        true
	'GlobalComponents':                        true
	'AllowedComponentProps':                   true
	'FunctionalComponent':                     true
	'ConcreteComponent':                       true
	'Component':                               true
	'SetupContext':                            true
	'ComponentInternalInstance':               true
	'getCurrentInstance':                      true
	'registerRuntimeCompiler':                 true
	'isRuntimeOnly':                           true
	'ComponentCustomElementInterface':         true
	'WatchEffectOptions':                      true
	'WatchOptions':                            true
	'watchEffect':                             true
	'watchPostEffect':                         true
	'watchSyncEffect':                         true
	'MultiWatchSources':                       true
	'watch':                                   true
	'HydrationStrategy':                       true
	'HydrationStrategyFactory':                true
	'hydrateOnIdle':                           true
	'hydrateOnVisible':                        true
	'hydrateOnMediaQuery':                     true
	'hydrateOnInteraction':                    true
	'AsyncComponentLoader':                    true
	'AsyncComponentOptions':                   true
	'defineAsyncComponent':                    true
	'useModel':                                true
	'TemplateRef':                             true
	'useTemplateRef':                          true
	'useId':                                   true
	'h':                                       true
	'ssrContextKey':                           true
	'useSSRContext':                           true
	'ErrorCodes':                              true
	'callWithErrorHandling':                   true
	'callWithAsyncErrorHandling':              true
	'handleError':                             true
	'initCustomFormatter':                     true
	'HMRRuntime':                              true
	'pushScopeId':                             true
	'popScopeId':                              true
	'withScopeId':                             true
	'withCtx':                                 true
	'renderList':                              true
	'toHandlers':                              true
	'renderSlot':                              true
	'createSlots':                             true
	'withMemo':                                true
	'isMemoSame':                              true
	'LegacyConfig':                            true
	'CompatVue':                               true
	'version':                                 true
	'warn':                                    true
	'devtools':                                true
	'setDevtoolsHook':                         true
	'DeprecationTypes':                        true
	'createElementVNode':                      true
	'WatchOptionsBase':                        true
	'nodeOps':                                 true
	'patchProp':                               true
	'TransitionProps':                         true
	'Transition':                              true
	'TransitionGroupProps':                    true
	'TransitionGroup':                         true
	'vShow':                                   true
	'withModifiers':                           true
	'withKeys':                                true
	'vModelText':                              true
	'vModelCheckbox':                          true
	'vModelRadio':                             true
	'vModelSelect':                            true
	'vModelDynamic':                           true
	'CSSProperties':                           true
	'AriaAttributes':                          true
	'StyleValue':                              true
	'ClassValue':                              true
	'HTMLAttributes':                          true
	'AnchorHTMLAttributes':                    true
	'AreaHTMLAttributes':                      true
	'AudioHTMLAttributes':                     true
	'BaseHTMLAttributes':                      true
	'BlockquoteHTMLAttributes':                true
	'ButtonHTMLAttributes':                    true
	'CanvasHTMLAttributes':                    true
	'ColHTMLAttributes':                       true
	'ColgroupHTMLAttributes':                  true
	'DataHTMLAttributes':                      true
	'DetailsHTMLAttributes':                   true
	'DelHTMLAttributes':                       true
	'DialogHTMLAttributes':                    true
	'EmbedHTMLAttributes':                     true
	'FieldsetHTMLAttributes':                  true
	'FormHTMLAttributes':                      true
	'HtmlHTMLAttributes':                      true
	'IframeHTMLAttributes':                    true
	'ImgHTMLAttributes':                       true
	'InsHTMLAttributes':                       true
	'InputTypeHTMLAttribute':                  true
	'InputAutoCompleteAttribute':              true
	'InputHTMLAttributes':                     true
	'KeygenHTMLAttributes':                    true
	'LabelHTMLAttributes':                     true
	'LiHTMLAttributes':                        true
	'LinkHTMLAttributes':                      true
	'MapHTMLAttributes':                       true
	'MenuHTMLAttributes':                      true
	'MediaHTMLAttributes':                     true
	'MetaHTMLAttributes':                      true
	'MeterHTMLAttributes':                     true
	'QuoteHTMLAttributes':                     true
	'ObjectHTMLAttributes':                    true
	'OlHTMLAttributes':                        true
	'OptgroupHTMLAttributes':                  true
	'OptionHTMLAttributes':                    true
	'OutputHTMLAttributes':                    true
	'ParamHTMLAttributes':                     true
	'ProgressHTMLAttributes':                  true
	'ScriptHTMLAttributes':                    true
	'SelectHTMLAttributes':                    true
	'SourceHTMLAttributes':                    true
	'StyleHTMLAttributes':                     true
	'TableHTMLAttributes':                     true
	'TextareaHTMLAttributes':                  true
	'TdHTMLAttributes':                        true
	'ThHTMLAttributes':                        true
	'TimeHTMLAttributes':                      true
	'TrackHTMLAttributes':                     true
	'VideoHTMLAttributes':                     true
	'WebViewHTMLAttributes':                   true
	'SVGAttributes':                           true
	'IntrinsicElementAttributes':              true
	'Events':                                  true
	'ReservedProps':                           true
	'NativeElements':                          true
	'VueElementConstructor':                   true
	'CustomElementOptions':                    true
	'defineCustomElement':                     true
	'defineSSRCustomElement':                  true
	'VueElement':                              true
	'useHost':                                 true
	'useShadowRoot':                           true
	'useCssModule':                            true
	'useCssVars':                              true
	'render':                                  true
	'hydrate':                                 true
	'createApp':                               true
	'createSSRApp':                            true
	'compileToFunction':                       true
	'compile':                                 true
}

fn (mut c Checker) lint_vue_prefer_import_from_vue(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.import_declaration {
				stats.checked++
				specifiers := t.list(node, .specifiers) or { []int{} }
				filename := c.vue_context_filename(abs_path)
				if specifiers.len == 0 && filename.ends_with('.d.ts') {
					continue
				}
				only_named := specifiers.all(t.typ(it) == .import_specifier)
				name_list := if only_named {
					specifiers.map(vpifv_module_export_name(t, t.node(it, .imported) or { -1 }))
				} else {
					[]string{}
				}
				mut fixable := true
				for specifier in specifiers {
					name := match t.typ(specifier) {
						.import_default_specifier { 'default' }
						.import_specifier {
							vpifv_module_export_name(t, t.node(specifier, .imported) or { -1 })
						}
						else { '' } // import all
					}
					if t.typ(specifier) == .import_namespace_specifier || name !in vpifv_vue3_export_names {
						fixable = false
						break
					}
				}
				c.vpifv_verify(t, t.node(node, .source) or { continue }, fixable, name_list, mut findings)
			}
			.export_named_declaration {
				source := t.node(node, .source) or { continue }
				stats.checked++
				specifiers := t.list(node, .specifiers) or { []int{} }
				name_list := specifiers.map(vpifv_module_export_name(t, t.node(it, .local) or { -1 }))
				fixable := name_list.all(it in vpifv_vue3_export_names)
				c.vpifv_verify(t, source, fixable, name_list, mut findings)
			}
			.export_all_declaration {
				source := t.node(node, .source) or { continue }
				stats.checked++
				c.vpifv_verify(t, source, false, [], mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vpifv_module_export_name is the `name` of an Identifier (upstream reads `.name`, which a
// string Literal does not have: undefined, never a name 'vue' exports).
fn vpifv_module_export_name(t &estree.EsTree, node int) string {
	if node < 0 || t.typ(node) != .identifier {
		return '\x00undefined'
	}
	return t.string_of(node, .name) or { '' }
}

fn (c &Checker) vpifv_verify(t &estree.EsTree, source int, fixable bool, name_list []string, mut findings []Finding) {
	value := t.get(source, .value)
	if value !is string {
		return
	}
	module := value as string
	if module !in vpifv_target_modules
		|| (name_list.len > 0 && name_list.all(it !in vpifv_vue3_export_names)) {
		return
	}
	finding := Finding{
		stmt:       c.es_tree_position(t, source)
		message_id: 'importedAtVue'
		data:       {
			'source': module
		}
	}
	findings << if fixable {
		c.with_fixes(finding, [fix_replace_range(t.nodes[source].start + 1, t.nodes[source].end - 1,
			'vue')]) or { finding }
	} else {
		finding
	}
}

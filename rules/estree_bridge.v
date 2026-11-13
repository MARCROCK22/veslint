module rules

import codepath
import estree
import jsregexp
import treesitter { node_parent }

// The rules ported on ESLint's own structures read the file as typescript-estree gives it (the
// estree module, checked against typescript-estree) and, for the ones that listen to code path
// events, ESLint's code path analysis of that tree (the codepath module, checked against ESLint's
// events). Both are built on first use, once per file.

// EsFileState tells whether the ESTree of the file was built: a tree with syntax errors has none
// (ESLint does not lint such a file).
enum EsFileState {
	unknown
	built
	failed
}

// es_tree is the ESTree of the file, or none when the file has syntax errors.
fn (mut c Checker) es_tree(root C.TSNode, abs_path string) ?&estree.EsTree {
	if c.file_es_state == .unknown {
		mut top := root
		for {
			top = node_parent(top) or { break }
		}
		tree := estree.convert_with(top, c.src, abs_path.to_lower().ends_with('.tsx'),
			estree.Options{
				module:       c.language.source_type == 'module'
				regexp_valid: fn (pattern string, flags string) bool {
					return jsregexp.regexp_new(estree.utf16_units(pattern), flags) != none
				}
			}) or {
			c.file_es_state = .failed
			return none
		}
		c.file_es = tree
		c.file_es_state = .built
	}
	if c.file_es_state == .failed {
		return none
	}
	return &c.file_es
}

// code_path_analysis is ESLint's code path analysis of the file (its events, code paths and
// segments), or none when the file has syntax errors.
fn (mut c Checker) code_path_analysis(root C.TSNode, abs_path string) ?&codepath.Analysis {
	t := c.es_tree(root, abs_path)?
	if !c.file_code_paths_built {
		c.file_code_paths = codepath.analyze(t)
		c.file_code_paths_built = true
	}
	return &c.file_code_paths
}

// reset_es_file forgets the trees of the previous file.
fn (mut c Checker) reset_es_file() {
	c.file_es_state = .unknown
	c.file_es = estree.EsTree{}
	c.file_es_by_ts = map[u64]int{}
	c.file_code_paths_built = false
	c.file_code_paths = codepath.Analysis{}
}

// es_index_of is the ESTree node a tree-sitter node of the file was converted to (the innermost
// one when several share it, as a ChainExpression and its member expression), for the helpers
// ported on tree-sitter's tree (the ReferenceTracker, the scope tree) that the rules on the ESTree
// use; none if it has none.
fn (mut c Checker) es_index_of(t &estree.EsTree, n C.TSNode) ?int {
	if c.file_es_by_ts.len == 0 {
		for i, node in t.nodes {
			if !node.has_ts {
				continue
			}
			key := node_key(node.ts)
			if previous := c.file_es_by_ts[key] {
				// The child made from the same node replaces its parent.
				if t.nodes[i].parent != previous {
					continue
				}
			}
			c.file_es_by_ts[key] = i
		}
	}
	return c.file_es_by_ts[node_key(n)] or { return none }
}

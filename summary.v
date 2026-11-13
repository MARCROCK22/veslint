module main

// `--summary`: instead of a line per problem, a table of the rules that reported problems, with
// how many and in how many files, from the rule with the most problems down.

// RuleCount is what the table says of a rule.
struct RuleCount {
mut:
	problems int
	errors   int
	warnings int
	files    int
	last     string // the last file counted, so a file counts once (files come one after another)
}

// RuleSummary gathers the problems of a run, by rule.
struct RuleSummary {
mut:
	counts map[string]RuleCount
}

// add counts a problem of `rule` in `file`: an error, or a warning when `warning`.
fn (mut s RuleSummary) add(rule string, file string, warning bool) {
	mut count := s.counts[rule] or { RuleCount{} }
	count.problems++
	if warning {
		count.warnings++
	} else {
		count.errors++
	}
	if count.last != file {
		count.files++
		count.last = file
	}
	s.counts[rule] = count
}

// table is the text of the table: a header and a row per rule, by problems (most first) and then
// by name; the name is aligned to the left and the numbers to the right. Empty without problems.
fn (s &RuleSummary) table() string {
	if s.counts.len == 0 {
		return ''
	}
	mut names := s.counts.keys()
	names.sort_with_compare(fn [s] (a &string, b &string) int {
		x := s.counts[*a] or { RuleCount{} }
		y := s.counts[*b] or { RuleCount{} }
		if x.problems != y.problems {
			return y.problems - x.problems
		}
		return compare_strings(a, b)
	})
	headers := ['Rule', 'Problems', 'Errors', 'Warnings', 'Files']
	mut rows := [][]string{}
	for name in names {
		c := s.counts[name] or { RuleCount{} }
		rows << [name, c.problems.str(), c.errors.str(), c.warnings.str(), c.files.str()]
	}
	mut widths := headers.map(it.len)
	for row in rows {
		for i, cell in row {
			if cell.len > widths[i] {
				widths[i] = cell.len
			}
		}
	}
	mut lines := [headers]
	lines << rows
	mut out := []string{}
	for row in lines {
		mut cells := []string{}
		for i, cell in row {
			cells << if i == 0 {
				cell + ' '.repeat(widths[i] - cell.len)
			} else {
				' '.repeat(widths[i] - cell.len) + cell
			}
		}
		out << cells.join('  ').trim_right(' ')
	}
	return out.join('\n') + '\n'
}

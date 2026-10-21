#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
usage: pr.sh <command> [base]

  base                      print the base ref, e.g. origin/main
  commits [base]            check every commit in base..HEAD against the commit rules
  comments [base]           list comment lines added since the merge base, committed or not
  reword <map-file> <base>  rewrite commit messages from '<sha> <message>' lines, base required
  ascii <file>...           list lines with non-ascii characters, e.g. em dashes

base defaults to origin/HEAD, then the repo's default branch on github, then origin/main
EOF
	exit 2
}

die() {
	echo "pr.sh: $*" >&2
	exit 2
}

base_ref() {
	local ref name
	if [ -n "${1:-}" ]; then
		echo "$1"
	elif ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); then
		echo "$ref"
	elif name=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) && [ -n "$name" ]; then
		echo "origin/$name"
	else
		echo origin/main
	fi
}

cmd_commits() {
	local base shas sha subject words problems failed=0
	base=$(base_ref "${1:-}")
	shas=$(git rev-list --reverse "$base..HEAD")
	if [ -z "$shas" ]; then
		echo "no commits ahead of $base"
		return 0
	fi
	for sha in $shas; do
		subject=$(git log -1 --format=%s "$sha")
		problems=""
		if [ -n "$(git log -1 --format='%(trailers:only,unfold)' "$sha")" ]; then
			problems="$problems  - has trailers"$'\n'
		elif [ -n "$(git log -1 --format=%b "$sha")" ]; then
			problems="$problems  - has a body"$'\n'
		fi
		if printf '%s' "$subject" | grep -q '[A-Z]'; then
			problems="$problems  - not lowercase"$'\n'
		fi
		if printf '%s' "$subject" | LC_ALL=C grep -q '[^A-Za-z0-9 ]'; then
			problems="$problems  - has punctuation or symbols"$'\n'
		fi
		words=$(printf '%s' "$subject" | wc -w | tr -d ' ')
		if [ "$words" -gt 8 ]; then
			problems="$problems  - $words words, max 8"$'\n'
		fi
		if [ -n "$problems" ]; then
			failed=1
			printf '%s %s\n%s' "$(git rev-parse --short "$sha")" "$subject" "$problems"
		fi
	done
	if [ "$failed" -eq 1 ]; then
		return 1
	fi
	echo "all commits pass"
}

cmd_comments() {
	local base mb
	base=$(base_ref "${1:-}")
	mb=$(git merge-base "$base" HEAD)
	cd "$(git rev-parse --show-toplevel)"
	local skip=(':(exclude)*.md' ':(exclude)*.mdx' ':(exclude)*.txt' ':(exclude)*.snap' ':(exclude)*.svg'
		':(exclude)*.lock' ':(exclude)*.lockb' ':(exclude)*-lock.json' ':(exclude)*-lock.yaml')
	local flags=(-U0 --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/)
	{
		git diff "${flags[@]}" --diff-filter=AMR "$mb" -- . "${skip[@]}"
		git ls-files -z --others --exclude-standard -- . "${skip[@]}" | while IFS= read -r -d '' f; do
			git diff "${flags[@]}" --no-index -- /dev/null "$f" || true
		done
	} | awk '
		function is_comment(s) {
			return s ~ /^[ \t]*(\/\/|\/\*|\*( |\/|$)|#( |#|$)|<!--|\{\/\*|-- )/ ||
				s ~ /[ \t](\/\/|\/\*)( |$)/ || s ~ /[ \t]#( |$)/ || s ~ /<!--/
		}
		function is_directive(s) {
			return s ~ /(eslint|oxlint|biome-ignore|prettier-ignore|@ts-(ignore|expect-error|nocheck|check)|noqa|type: ignore|pylint:|svelte-ignore|istanbul ignore|c8 ignore|v8 ignore|#region|#endregion|<reference )/
		}
		/^\+\+\+ / { file = $0; sub(/^\+\+\+ b\//, "", file); next }
		/^@@ / { split($3, a, ","); line = substr(a[1], 2) + 0; next }
		/^\+/ {
			text = substr($0, 2)
			if (is_comment(text) && !is_directive(text)) {
				sub(/^[ \t]+/, "", text)
				printf "%s:%d: %s\n", file, line, text
			}
			line++
		}
	'
}

cmd_msg() {
	local new
	new=$(awk -v c="$GIT_COMMIT" '$1 == c { sub(/^[^ ]+ /, ""); print; exit }' "$1")
	if [ -n "$new" ]; then
		cat >/dev/null
		printf '%s\n' "$new"
	else
		cat
	fi
}

cmd_reword() {
	local map=${1:-} base branch range norm line sha msg full self
	[ -f "$map" ] || die "reword needs a file of '<sha> <message>' lines"
	[ -n "${2:-}" ] || die "reword needs an explicit base, e.g. pr.sh reword $map origin/next"
	base=$2
	branch=$(git symbolic-ref -q --short HEAD) || die "not on a branch"
	git diff --quiet && git diff --cached --quiet || die "commit or stash changes first"
	range=$(git rev-list "$base..HEAD")
	# never rewrite commits another remote branch already has, a wrong base would rewrite them all
	local others all own
	others=$(git for-each-ref --format='^%(refname)' refs/remotes |
		grep -Fvx -e "^refs/remotes/origin/$branch" -e '^refs/remotes/origin/HEAD' || true)
	all=$(git rev-list --count "$base..HEAD")
	# shellcheck disable=SC2086
	own=$(git rev-list --count "$base..HEAD" $others)
	[ "$all" -eq "$own" ] ||
		die "$((all - own)) commits in $base..HEAD are on other remote branches, is $base the right base?"
	norm=$(mktemp)
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$line" ] || continue
		sha=${line%% *}
		msg=${line#* }
		[ "$sha" != "$line" ] || die "no message on line '$line'"
		full=$(git rev-parse -q --verify "$sha^{commit}") || die "unknown commit $sha"
		printf '%s\n' "$range" | grep -qx "$full" || die "$sha is not in $base..HEAD"
		printf '%s %s\n' "$full" "$msg" >>"$norm"
	done <"$map"
	self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
	FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f \
		--msg-filter "'$self' _msg '$norm'" -- "$base..$branch" >/dev/null
	git update-ref -d "refs/original/refs/heads/$branch" 2>/dev/null || true
	rm -f "$norm"
	git log --format='%h %s' "$base..HEAD"
}

cmd_ascii() {
	[ $# -gt 0 ] || die "ascii needs files to check"
	perl -ne '
		if (/[^\x00-\x7F]/) { print "$ARGV:$.: $_"; $bad = 1 }
		close ARGV if eof;
		END { exit($bad ? 1 : 0) }
	' "$@"
}

case "${1:-}" in
	base) base_ref "${2:-}" ;;
	ascii)
		shift
		cmd_ascii "$@"
		;;
	commits) cmd_commits "${2:-}" ;;
	comments) cmd_comments "${2:-}" ;;
	reword) cmd_reword "${2:-}" "${3:-}" ;;
	_msg) cmd_msg "$2" ;;
	*) usage ;;
esac

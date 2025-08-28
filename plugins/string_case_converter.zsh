scc() {
	# Internal helper functions (not exposed externally)
	
	# Helper function for capitalizing first ASCII letter only
	_capitalize_first_ascii() {
		local w="$1"
		if [ -z "$w" ]; then
			printf ''
			return
		fi
		
		local first="${w:0:1}"
		local rest="${w:1}"
		
		# Only capitalize if first char is ASCII letter
		if [[ "$first" =~ [a-z] ]]; then
			first=$(printf '%s' "$first" | tr 'a-z' 'A-Z')
		fi
		
		printf '%s%s' "$first" "$rest"
	}

	# Efficient case conversion for ASCII letters only
	_ascii_case_convert() {
		local input="$1" mode="$2"
		case "$mode" in
			upper)
				# Use tr for efficient batch conversion
				printf '%s' "$input" | tr 'a-z' 'A-Z'
				;;
			lower)
				printf '%s' "$input" | tr 'A-Z' 'a-z'
				;;
			*)
				printf '%s' "$input"
				;;
		esac
	}

	# JSON escape function (optimized for common cases)
	_json_escape() {
		local s="$1"
		# Handle most common escape sequences
		s=${s//\\/\\\\}
		s=${s//\"/\\\"}
		s=${s//$'\n'/\\n}
		s=${s//$'\r'/\\r}
		s=${s//$'\t'/\\t}
		printf '%s' "$s"
	}
	# Usage:
	#   string_case -f <format> "input"         # convert once
	#   echo "input" | string_case -f <format>
	#   string_case --alfred "input"            # Alfred Script Filter JSON
	#   string_case --list                       # list formats
	#   string_case --help

	local format="" input="" mode="convert"

	while [ $# -gt 0 ]; do
		case "$1" in
			-f|--format)
				shift || true
				format="${1:-}"
				;;
			--alfred)
				mode="alfred"
				;;
			--list)
				mode="list"
				;;
			-h|--help)
				cat <<EOF
string_case - Convert strings between common case styles

Usage:
  string_case -f <format> "input string"
  echo "input string" | string_case -f <format>
  string_case --alfred "input string"
  string_case --list

Formats (aliases):
  pascal | PascalCase | 大驼峰
  camel  | camelCase  | 小驼峰
  snake  | snake_case | 小蛇形
  snake_upper | SNAKE_CASE | 大蛇形
  snake_cap | Capitalized_Snake_Case | 首字母大写蛇形
  kebab  | kebab-case
  dot    | dot.case
  upper  | UPPER | 全大写
  lower  | lower | 全小写
EOF
				return 0
				;;
			--)
				shift
				break
				;;
			-*)
				printf 'Unknown option: %s\n' "$1" >&2
				return 2
				;;
			*)
				if [ -z "${input}" ]; then
					input="$1"
				else
					input+=" $1"
				fi
				;;
		esac
		shift || true
	done

	# If no explicit input, read from stdin
	if [ -z "${input}" ] && [ ! -t 0 ]; then
		input=$(cat)
	fi

	# Centralized empty input handling
	if [ -z "${input}" ]; then
		case "${mode}" in
			alfred)
				printf '{"items": []}'
				return 0
				;;
			list)
				# List mode doesn't need input, handled later
				;;
			*)
				printf 'Error: no input string provided.\n' >&2
				return 2
				;;
		esac
	fi

	if [ "${mode}" = "list" ]; then
		cat <<EOF
pascal
camel
snake
snake_upper
snake_cap
kebab
dot
upper
lower
EOF
		return 0
	fi

	# Map alias to canonical format
	local fmt="${format}"
	case "${fmt}" in
		pascal|PascalCase|大驼峰) fmt="pascal" ;;
		camel|camelCase|小驼峰) fmt="camel" ;;
		snake|snake_case|小蛇形) fmt="snake" ;;
		snake_upper|SNAKE_CASE|大蛇形) fmt="snake_upper" ;;
		snake_cap|Capitalized_Snake_Case|首字母大写蛇形) fmt="snake_cap" ;;
		kebab|kebab-case) fmt="kebab" ;;
		dot|dot-case|dot.case) fmt="dot" ;;
		upper|UPPER|全大写) fmt="upper" ;;
		lower|LOWER|全小写) fmt="lower" ;;
		*) 
			if [ -n "$format" ]; then
				fmt=""  # Invalid format specified
			fi
			;;
	esac

	if [ "${mode}" = "convert" ]; then
		if [ -z "${fmt}" ]; then
			printf 'Error: format not specified or invalid.\n' >&2
			return 2
		fi
		# Remove duplicate input check - already handled above
	fi

	# Unified text normalization with intelligent Unicode handling
	local norm="${input}"
	
	# Strategy: Preserve Unicode words that are space-separated, remove adjacent Unicode
	
	# Step 1: Detect Unicode characters and their context
	local has_spaced_unicode=false
	local has_adjacent_unicode=false
	
	# Check for Unicode words with spaces around them (standalone Unicode words)
	if printf '%s' "$norm" | LC_ALL=C grep -qE '(^|[[:space:]])[^a-zA-Z0-9[:space:][:punct:]]+([[:space:]]|$)'; then
		has_spaced_unicode=true
	fi
	
	# Check for Unicode adjacent to ASCII (no spaces)
	if printf '%s' "$norm" | LC_ALL=C grep -qE '[a-zA-Z0-9][^a-zA-Z0-9[:space:][:punct:]]|[^a-zA-Z0-9[:space:][:punct:]][a-zA-Z0-9]'; then
		has_adjacent_unicode=true
	fi
	
	# Step 2: Process based on Unicode context
	if [[ "$has_adjacent_unicode" == "true" ]]; then
		# Remove adjacent Unicode characters (treat as separators)
		LC_ALL=C norm=$(printf '%s' "$norm" \
			| sed -E 's/([a-zA-Z0-9])([^a-zA-Z0-9[:space:][:punct:]])/\1 \2/g' \
			| sed -E 's/([^a-zA-Z0-9[:space:][:punct:]])([a-zA-Z0-9])/\1 \2/g' \
			| sed -E 's/[^a-zA-Z0-9[:space:][:punct:]]//g')
	fi
	# If only spaced Unicode (no adjacent), preserve it naturally in processing
	
	# Step 3: Standard text processing
	# Handle punctuation as separators
	norm=$(printf '%s' "$norm" \
		| sed -E 's/[[:punct:]]+/ /g')
	# Split numbers from letters
	norm=$(printf '%s' "$norm" \
		| sed -E 's/([a-zA-Z])([0-9])/\1 \2/g' \
		| sed -E 's/([0-9])([a-zA-Z])/\1 \2/g')
	# Handle camelCase
	norm=$(printf '%s' "$norm" \
		| sed -E 's/([A-Z]+)([A-Z][a-z])/\1 \2/g' \
		| sed -E 's/([a-z0-9])([A-Z])/\1 \2/g')
	# Clean up spaces
	norm=$(printf '%s' "$norm" \
		| sed -E 's/[[:space:]]+/ /g' \
		| sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
	
	# Convert to lowercase while preserving Unicode
	local norm_lower=""
	local i char
	for (( i=0; i<${#norm}; i++ )); do
		char="${norm:$i:1}"
		if [[ "$char" =~ [A-Z] ]]; then
			norm_lower+=$(printf '%s' "$char" | tr 'A-Z' 'a-z')
		else
			norm_lower+="$char"
		fi
	done
	
	local -a words=()
	if [ -n "${norm_lower}" ]; then
		# Use portable word splitting that works in both bash and zsh
		if [[ "$norm_lower" =~ [[:space:]] ]]; then
			# Convert spaces to newlines and process
			local temp_split
			temp_split=$(printf '%s' "$norm_lower" | tr ' ' '\n')
			local word
			while IFS= read -r word; do
				[ -n "$word" ] && words+=("$word")
			done <<< "$temp_split"
		else
			words=("$norm_lower")
		fi
	fi

	# Optimized conversion functions with input validation
	_convert_style() {
		local style="$1"
		local out="" i w
		
		case "$style" in
			pascal)
				for w in "${words[@]}"; do
					out+="$(_capitalize_first_ascii "$w")"
				done
				printf '%s' "$out"
				;;
			camel)
				i=0
				for w in "${words[@]}"; do
					if [ $i -eq 0 ]; then
						out+="$w"
					else
						out+="$(_capitalize_first_ascii "$w")"
					fi
					i=$((i+1))
				done
				printf '%s' "$out"
				;;
			snake)
				printf '%s' "${norm_lower// /_}"
				;;
			snake_upper)
				_ascii_case_convert "${norm_lower// /_}" "upper"
				;;
			snake_cap)
				i=0
				for w in "${words[@]}"; do
					if [ $i -gt 0 ]; then out+="_"; fi
					out+="$(_capitalize_first_ascii "$w")"
					i=$((i+1))
				done
				printf '%s' "$out"
				;;
			kebab)
				printf '%s' "${norm_lower// /-}"
				;;
			dot)
				printf '%s' "${norm_lower// /.}"
				;;
			upper)
				_ascii_case_convert "$input" "upper"
				;;
			lower)
				_ascii_case_convert "$input" "lower"
				;;
            *) 
				printf '' 
				return 2 
				;;
		esac
	}

	if [ "${mode}" = "convert" ]; then
		if [ -z "${fmt}" ]; then
			printf 'Error: format not specified or invalid.\n' >&2
			return 2
		fi
		
		# Handle edge case: empty normalized input for word-based formats
		if [ ${#words[@]} -eq 0 ] && [[ ! "$fmt" =~ ^(upper|lower)$ ]]; then
			printf ''
			return 0
		fi
		
		_convert_style "$fmt"
		return 0
	fi

	# Alfred Script Filter mode: optimized batch processing
	local styles=(pascal camel snake snake_upper snake_cap kebab dot upper lower)
	local labels=(
		'PascalCase | 大驼峰'
		'camelCase | 小驼峰'
		'snake_case | 小蛇形'
		'SNAKE_CASE | 大蛇形'
		'Capitalized_Snake_Case | 首字母大写蛇形'
		'kebab-case'
		'dot.case'
		'UPPER | 全大写'
		'lower | 全小写'
	)

	# Pre-compute all conversion results efficiently
	local -a values=()
	local style_value
	for style in "${styles[@]}"; do
		style_value=$(_convert_style "$style")
		values+=("$style_value")
	done

	printf '{"items": ['
	local first_item=1 value label esc_title esc_arg esc_sub
	for i in "${!styles[@]}"; do
		value="${values[$i]}"
		# Skip empty results
		[ -z "$value" ] && continue
		
		label="${labels[$i]}"
		esc_title=$(_json_escape "$value")
		esc_arg="$esc_title"
		esc_sub=$(_json_escape "$label")
		
		if [ $first_item -eq 0 ]; then printf ','; else first_item=0; fi
		printf '{"title":"%s","subtitle":"%s","arg":"%s","text":{"copy":"%s","largetype":"%s"}}' \
			"$esc_title" "$esc_sub" "$esc_arg" "$esc_arg" "$esc_title"
	done
	printf ']}'
}

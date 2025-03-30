set -e
FORCE_COLORS=1
. ./common.sh
set +e

assert_not "" "${COLOR_BLUE}" "colors are not loaded"

input="package"
assert_ret 0 stripansi "${input}" stripped
assert "package" "${stripped}" "stripansi output should match"

input="${COLOR_BLUE}package two"
assert_ret 0 stripansi "${input}" stripped
assert "package two" "${stripped}" "stripansi output should match"

input="${COLOR_BLUE}package${COLOR_RESET}"
assert_ret 0 stripansi "${input}" stripped
assert "package" "${stripped}" "stripansi output should match"

input="${COLOR_BLUE}package${COLOR_RESET} "
assert_ret 0 stripansi "${input}" stripped
assert "package " "${stripped}" "stripansi output should match"

input=" ${COLOR_BLUE}package${COLOR_RESET}"
assert_ret 0 stripansi "${input}" stripped
assert " package" "${stripped}" "stripansi output should match"

input=" ${COLOR_BLUE}package${COLOR_RESET} "
assert_ret 0 stripansi "${input}" stripped
assert " package " "${stripped}" "stripansi output should match"

input="${COLOR_BLUE}pa${COLOR_BOLD}${COLOR_WHITE}c${COLOR_RESET}ka${COLOR_BG_CYAN}ge${COLOR_RESET}"
assert_ret 0 stripansi "${input}" stripped
assert "package" "${stripped}" "stripansi output should match"

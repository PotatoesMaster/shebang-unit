# Shebang unit all in one source file

#Beginning of assertion.sh
function assertion::equal() {
	local expected=$1; local actual=$2
	if [[ "${expected}" != "${actual}" ]]; then
		assertion::_assertion_failed "Actual : <${actual}>, expected : <${expected}>."
	fi
}

function assertion::string_contains() {
	local container=$1; local contained=$2
	if ! assertion::_string_contains "${container}" "${contained}"; then
		assertion::_assertion_failed "String: <${container}> does not contain: <${contained}>."
	fi
}

function assertion::string_does_not_contain() {
	local container=$1; local contained=$2
	if assertion::_string_contains "${container}" "${contained}"; then
		assertion::_assertion_failed "String: <${container}> contains: <${contained}>."
	fi
}

function assertion::_string_contains() {
	local container=$1; local contained=$2
	[[ "${container}" == *"${contained}"* ]]
}

function assertion::status_code_is_success() {
	local status_code=$1; local custom_message=$2
	if (( ${status_code} != ${SUCCESS_STATUS_CODE} )); then
		assertion::_assertion_failed "Status code is failure instead of success." "${custom_message}"
	fi
}

function assertion::status_code_is_failure() {
	local status_code=$1; local custom_message=$2
	if (( ${status_code} == ${SUCCESS_STATUS_CODE} )); then
		assertion::_assertion_failed "Status code is success instead of failure." "${custom_message}"
	fi
}

function assertion::_assertion_failed() {
	local message=$1; local custom_message=$2
	local message_to_use="$(assertion::_get_assertion_message_to_use "${message}" "${custom_message}")"
	printf "Assertion failed. ${message_to_use}\n"
	exit ${FAILURE_STATUS_CODE}
}

function assertion::_get_assertion_message_to_use() {
	local message=$1; local custom_messsage=$2
	if [[ -n "${custom_messsage}" ]]; then
		printf "%s %s\n" "${message}" "${custom_messsage}"
	else
		printf "${message}\n"
	fi
}
#End of assertion.sh

#Beginning of parser.sh
_GLOBAL_SETUP_FUNCTION_NAME="globalSetup"
_GLOBAL_TEARDOWN_FUNCTION_NAME="globalTeardown"
_SETUP_FUNCTION_NAME="setup"
_TEARDOWN_FUNCTION_NAME="teardown"

function parser::find_global_setup_function_in_file() {
	local file=$1
	parser::_find_functions_in_file "${file}" | grep "${_GLOBAL_SETUP_FUNCTION_NAME}"
}

function parser::find_global_teardown_function_in_file() {
	local file=$1
	parser::_find_functions_in_file "${file}" | grep "${_GLOBAL_TEARDOWN_FUNCTION_NAME}"
}

function parser::find_setup_function_in_file() {
	local file=$1
	parser::_find_functions_in_file "${file}" | grep "${_SETUP_FUNCTION_NAME}"
}

function parser::find_teardown_function_in_file() {
	local file=$1
	parser::_find_functions_in_file "${file}" | grep "${_TEARDOWN_FUNCTION_NAME}"
}

function parser::find_test_functions_in_file() {
	local file=$1
	parser::_find_functions_in_file "${file}" | parser::_filter_private_functions | parser::_filter_special_functions
}

function parser::_find_functions_in_file() {
	local file=$1
	grep -o "^function.*()" "${file}" | parser::_get_function_name_from_declaration | tr -d " "
}

function parser::_filter_private_functions() {
	grep -v "^_.*"
}

function parser::_filter_special_functions() {
	grep -v "${_SETUP_FUNCTION_NAME}\|${_TEARDOWN_FUNCTION_NAME}\|${_GLOBAL_SETUP_FUNCTION_NAME}\|${_GLOBAL_TEARDOWN_FUNCTION_NAME}"
}

function parser::_get_function_name_from_declaration() {
	sed "s/function\(.*\)()/\1/"
}
#End of parser.sh

#Beginning of runner.sh
_GREEN_COLOR_CODE="\\033[1;32m"
_RED_COLOR_CODE="\\033[1;31m"
_DEFAULT_COLOR_CODE="\\e[0m"

_DEFAULT_TEST_FILE_PATTERN=*_test.sh

function runner::run_all_test_files_in_directory() {
	local directory=$1; local overriden_test_file_pattern=$2

	runner::_initialise_tests_execution
	local test_file_pattern="$(system::get_string_or_default_if_empty "${overriden_test_file_pattern}" "${_DEFAULT_TEST_FILE_PATTERN}")"
	runner::_run_all_test_files_with_pattern_in_directory "${test_file_pattern}" "${directory}"
	runner::_print_tests_results
	runner::_tests_are_successful
}

function runner::_initialise_tests_execution() {
	_GREEN_TESTS_COUNT=0
	_RED_TESTS_COUNT=0
	_EXECUTION_BEGINING_DATE="$(system::get_date_in_seconds)"
}

function runner::_run_all_test_files_with_pattern_in_directory() {
	local test_file_pattern=$1; local directory=$2

	local file; for file in $(find "${directory}" -name ${test_file_pattern}); do
		runner::_run_test_file "${file}"
	done
}

function runner::_run_test_file() {
	local file=$1
	printf "[File] ${file}\n"
	source "${file}"
	runner::_call_global_setup_in_file "${file}"
	runner::_call_all_tests_in_file "${file}"
	runner::_call_global_teardown_in_file "${file}"
	printf "\n"
}

function runner::_call_global_setup_in_file() {
	local file=$1
	runner::_call_function_if_existing "$(parser::find_global_setup_function_in_file "${file}")"
}

function runner::_call_global_teardown_in_file() {
	local file=$1
	runner::_call_function_if_existing "$(parser::find_global_teardown_function_in_file "${file}")"
}

function runner::_call_all_tests_in_file() {
	local file=$1
	local test_function; for test_function in $(parser::find_test_functions_in_file "${file}"); do
		runner::_call_test_function_in_the_middle_of_setup_and_teardown "${test_function}" "${file}"
	done
}

function runner::_call_test_function_in_the_middle_of_setup_and_teardown() {
	local test_function=$1; local file=$2

	printf "[Test] ${test_function}\n"
	( runner::_call_setup_in_file "${file}" &&
	( ${test_function} ) &&
	runner::_call_teardown_in_file "${file}" )
	runner::_parse_test_function_result "${test_function}" $?
}

function runner::_call_setup_in_file() {
	local file=$1
	runner::_call_function_if_existing "$(parser::find_setup_function_in_file "${file}")"
}

function runner::_call_teardown_in_file() {
	local file=$1
	runner::_call_function_if_existing "$(parser::find_teardown_function_in_file "${file}")"
}

function runner::_parse_test_function_result() {
	local test_function=$1; local status_code=$2

	if (( ${status_code} == ${SUCCESS_STATUS_CODE} )); then
		(( _GREEN_TESTS_COUNT++ ))
		runner::_print_with_color "OK" ${_GREEN_COLOR_CODE}
	else
		(( _RED_TESTS_COUNT++ ))
		runner::_print_with_color "KO" ${_RED_COLOR_CODE}
	fi
}

function runner::_print_tests_results() {
	printf "[Results]\n"
	local color="$(runner::_getColorCodeForTestsResult)"
	local execution_time="$(runner::_get_execution_time)"
	runner::_print_with_color "Green tests : ${_GREEN_TESTS_COUNT}, red : ${_RED_TESTS_COUNT} in ${execution_time}s" "${color}"
}

function runner::_getColorCodeForTestsResult() {
	local color_code=${_GREEN_COLOR_CODE}
	if ! runner::_tests_are_successful; then
		color_code=${_RED_COLOR_CODE}
	fi
	printf "${color_code}"
}

function runner::_get_execution_time() {
	local ending_date="$(system::get_date_in_seconds)"
	printf "$((${ending_date} - ${_EXECUTION_BEGINING_DATE}))"
}

function runner::_print_with_color() {
	local text=$1; local color_code=$2
	system::print_with_color "${text}" "${color_code}" "${_DEFAULT_COLOR_CODE}"
}

function runner::_tests_are_successful() {
	(( ${_RED_TESTS_COUNT} == 0 ))
}

function runner::_call_function_if_existing() {
	local function=$1
	if [[ -n "${function}" ]]; then
		eval ${function}
	fi
}
#End of runner.sh

#Beginning of system.sh
SUCCESS_STATUS_CODE=0
FAILURE_STATUS_CODE=1

function system::get_string_or_default_if_empty() {
	local string=$1; local default_string=$2
	local result=${string}
	if [[ -z "${string}" ]]; then
		result="${default_string}"
	fi
	printf "${result}"
}

function system::get_date_in_seconds() {
	date +%s
}

function system::print_with_color() {
	local text=$1; local color=$2; local default_color=$3
	printf "${color}${text}${default_color}\n"
}
#End of system.sh

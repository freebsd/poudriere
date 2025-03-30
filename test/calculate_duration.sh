. ./common.sh

contexts="$(mktemp -ut test_contexts)"
cat > "${contexts}" <<-EOF
seconds=0;		expected_duration=00:00:00;
seconds=1;		expected_duration=00:00:01;
seconds=60;		expected_duration=00:01:00;
seconds=61;		expected_duration=00:01:01;
seconds=3600;		expected_duration=01:00:00;
seconds=3660;		expected_duration=01:01:00;
seconds=3665;		expected_duration=01:01:05;
seconds=86400;		expected_duration=1D:00:00:00;
seconds=86460;		expected_duration=1D:00:01:00;
seconds=90000;		expected_duration=1D:01:00:00;
seconds=604800;		expected_duration=7D:00:00:00;
seconds=691200;		expected_duration=8D:00:00:00;
seconds=691261;		expected_duration=8D:00:01:01;
seconds=31536000;	expected_duration=365D:00:00:00;
EOF

set_test_contexts "${contexts}" "" ""

while get_test_context; do
	duration=
	assert_ret 0 calculate_duration duration "${seconds:?}"
	assert "${expected_duration}" "${duration}" "calculate_duration()"

	timestamp="$(TIME_START="${seconds}" timestamp -d)"
	assert "0" "$?"
	assert "${expected_duration}" "${timestamp}" "./timestamp -d"
done

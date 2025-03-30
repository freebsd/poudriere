. ./common.sh

mypid="$(getpid)"
assert 0 "$?" getpid
assert "$$" "${mypid}" ''

(
	mypid="$(getpid)"
	assert 0 "$?" ''
	assert_not "$$" "${mypid}" ''
	assert "$(sh -c 'echo $PPID')" "${mypid}" ''
)
assert 0 "$?" ''

#!/bin/sh
# $FreeBSD$
#
# Read a single errorlogfile and output a reason.
#
# Originally factored out of portbuild's processonelog
# XXX MCL note: not up-to-date with:
# http://www.marcuscom.com:8080/cgi-bin/cvsweb.cgi/portstools/tinderbox/sql/values.{lp|pfp|pfr}

filename=$1

if bzgrep -qE "(Error: mtree file ./etc/mtree/BSD.local.dist. is missing|error in pkg_delete|filesystem was touched prior to .make install|list of extra files and directories|list of files present before this port was installed|list of filesystem changes from before and after|Error: Files or directories left over|Error: Filesystem touched during build)" $1; then
  reason="mtree"
elif bzgrep -qE "(Error: Filesystem touched during stage|Error: stage-qa failures)" $1; then
  reason="stage"
# note: must run before the configure_error check
elif bzgrep -qE "Configuration .* not supported" $1; then
  reason="arch"
elif bzgrep -qE '(configure: error:|Script.*configure.*failed unexpectedly|script.*failed: here are the contents of)' $1; then
  if bzgrep -qE "configure: error: cpu .* not supported" $1; then
    reason="arch"
  elif bzgrep -qE "configure: error: [Pp]erl (5.* required|version too old)" $1; then
    reason="perl"
  elif bzgrep -q 'sem_wait: Invalid argument' $1; then
    reason="sem_wait"
  else
    reason="configure_error"
  fi
elif bzgrep -q "invalid DSO for symbol" $1; then
  reason="missing_LDFLAGS"
elif bzgrep -q "Couldn't fetch it - please try" $1; then
  reason="fetch"
elif bzgrep -q "Error: shared library \".*\" does not exist" $1; then
  reason="LIB_DEPENDS"
elif bzgrep -qE "\.(c|cc|cxx|cpp|h|y)[0-9:]+ .+\.[hH](: No such file|' file not found)" $1; then
  reason="missing_header"
elif bzgrep -qE '(nested function.*declared but never defined|warning: nested extern declaration)' $1; then
  reason="nested_declaration"
elif bzgrep -qE 'error: .* create dynamic relocation .* against symbol: .* in readonly segment' $1; then
  reason="lld_linker_error"
# note: must be run before compiler_error
elif bzgrep -q '#warning "this file includes <sys/termios.h>' $1; then
  reason="termios"
# note: must be run before compiler_error
elif bzgrep -qE "(#error define UTMP_FILENAME in config.h|error: ._PATH_UTMP. undeclared|error: .struct utmpx. has no member named .ut_name|error: invalid application of .sizeof. to incomplete type .struct utmp|utmp.h> has been replaced by <utmpx.h)" $1; then
  reason="utmp_x"
elif bzgrep -qE '(parse error|too (many|few) arguments to|argument.*doesn.*prototype|incompatible type for argument|conflicting types for|undeclared \(first use (in |)this function\)|incorrect number of parameters|has incomplete type and cannot be initialized|error: storage size.* isn.t known)' $1; then
  reason="compiler_error"
elif bzgrep -qE '(ANSI C.. forbids|is a contravariance violation|changed for new ANSI .for. scoping|[0-9]: passing .* changes signedness|lacks a cast|redeclared as different kind of symbol|invalid type .* for default argument to|wrong type argument to unary exclamation mark|duplicate explicit instantiation of|incompatible types in assignment|assuming . on overloaded member function|call of overloaded .* is ambiguous|declaration of C function .* conflicts with|initialization of non-const reference type|using typedef-name .* after|[0-9]: size of array .* is too large|fixed or forbidden register .* for class|assignment of read-only variable|error: label at end of compound statement|error:.*(has no|is not a) member|error:.*is (private|protected)|error: uninitialized member|error: unrecognized command line option)' $1; then
  reason="new_compiler_error"
# XXX MCL must preceed badc++
elif bzgrep -qE "error: invalid conversion from .*dirent" $1; then
  reason="dirent"
# s/ISO C++ does not support/ISO C++/
elif bzgrep -qE '(syntax error before|friend declaration|no matching function for call to|.main. must return .int.|invalid conversion from|cannot be used as a macro name as it is an operator in C\+\+|is not a member of type|after previous specification in|no class template named|because worst conversion for the former|better than worst conversion|no match for.*operator|no match for call to|undeclared in namespace|is used as a type, but is not|error: array bound forbidden|error: class definition|error: expected constructor|error: there are no arguments|error:.*cast.*loses precision|ISO C\+\+|error: invalid pure specifier|error: invalid (argument type|integral value|operand|token|use of a cast|value)|error: expected.*(at end of declaration|expression|identifier)|error:.*not supported)' $1; then
  reason="bad_C++_code"
elif bzgrep -qE 'error: (array type has incomplete element type|conflicts with new declaration|expected.*before .class|expected primary expression|extra qualification .* on member|.*has incomplete type|invalid cast from type .* to type|invalid lvalue in (assignment|decrement|increment|unary)|invalid storage class for function|lvalue required as (increment operator|left operand)|.*should have been declared inside|static declaration of.*follows non-static declaration|two or more data types in declaration specifiers|.* was not declared in this scope)' $1; then
  reason="gcc4_error"
elif bzgrep -qE '(/usr/libexec/elf/ld: cannot find|undefined reference to|cannot open -l.*: No such file|error: linker command failed with exit code 1)' $1; then
  reason="linker_error"
elif bzgrep -q 'install: .*: No such file' $1; then
  reason="install_error"
elif bzgrep -qE "(conflicts with installed package|installs files into the same place|is already installed - perhaps an older version|You may wish to ..make deinstall.. and install this port again)" $1; then
  reason="depend_object"
elif bzgrep -q "core dumped" $1; then
  reason="coredump"
# linimon would _really_ like to understand how to fix this problem
elif bzgrep -q "pkg_add: tar extract.*failed!" $1; then
  reason="truncated_distfile"
elif bzgrep -qE "(error: a parameter list without types|error: C++ requires a type specifier|error: allocation of incomplete type|error: array is too large|error: binding of reference|error: call to func.*neither visible|error: called object type|error: cannot combine with previous.*specifier|error: cannot initialize (a parameter|a variable|return object)|error: cannot pass object|error:.*cast from pointer|error: comparison of unsigned.*expression.*is always|error: conversion.*(is ambiguous|specifies type)|error:.*converts between pointers to integer|error: declaration of.*shadows template parameter|error:.*declared as an array with a negative size|error: default arguments cannot be added|error: default initialization of an object|error: definition.*not in a namespace|error:.*directive requires a positive integer argument|error: elaborated type refers to a typedef|error: exception specification|error: explicit specialization.*after instantiation|error: explicitly assigning a variable|error: expression result unused|error: fields must have a constant size|error: flexible array member|error: (first|second) (argument|parameter) of .main|error: format string is not a string literal|error: function.*is not needed|error: global register values are not supported|error:.*hides overloaded virtual function|error: if statement has empty body|error: illegal storage class on function|error: implicit (conversion|declaration|instantiation)|error: indirection.*will be deleted|error: initializer element is not.*constant|error: initialization of pointer|error: indirect goto might cross|error:.*is a (private|protected) member|error: member (of anonymous union|reference)|error: no matching member|error: non-const lvalue|error: non-void function.*should return a value|error: no (matching constructor|member named|viable overloaded)|error: parameter.*must have type|error: passing.*(a.*value|incompatible type)|error: qualified reference|error: redeclaration of.*built-in type|error:.*requires a (constant expression|pointer or reference|type specifier)|error: redefinition of|error: switch condition has boolean|error: taking the address of a temporary object|error: target.*conflicts with declaration|error:.*unable to pass LLVM bit-code files to linker|error: unexpected token|error: unknown (machine mode|type name)|error: unsupported (inline asm|option)|error: unused (function|parameter)|error: use of (GNU old-style field designator|undeclared identifier|unknown builtin)|error: using the result of an assignment|error: variable.*is unitialized|error: variable length array|error: void function.*should not return a value|the clang compiler does not support|Unknown depmode none)" $1; then
  reason="clang"

# below here are the less common items

# XXX MCL "file not recognized: File format not recognized" can be clang
elif bzgrep -qE "(.s: Assembler messages:|Cannot (determine .* target|find the byte order) for this architecture|^cc1: bad value.*for -mcpu.*switch|could not read symbols: File in wrong format|[Ee]rror: [Uu]nknown opcode|error.*Unsupported architecture|ENDIAN must be defined 0 or 1|failed to merge target-specific data|(file not recognized|failed to set dynamic section sizes): File format not recognized|impossible register constraint|inconsistent operand constraints in an .asm|Invalid configuration.*unknown.*machine.*unknown not recognized|invalid lvalue in asm statement|is only for.*, and you are running|not a valid 64 bit base/index expression|relocation R_X86_64_32.*can not be used when making a shared object|relocation truncated to fit: |shminit failed: Function not implemented|The target cpu, .*, is not currently supported.|This architecture seems to be neither big endian nor little endian|unknown register name|Unable to correct byte order|Unsupported platform, sorry|won't run on this architecture)" $1;  then
  reason="arch"
elif bzgrep -qE "(Cannot exec cc|cannot find program cc|cc: No such file or directory|cc.*must be installed to build|compiler not found|error: no acceptable C compiler|g\+\+: No such file or directory|g\+\+.*not found)" $1; then
  reason="assumes_gcc"
elif bzgrep -qE "autoconf([0-9\-\.]*): (not found|No such file or directory)" $1; then
  reason="autoconf"
elif bzgrep -q "autoheader: not found" $1; then
  reason="autoheader"
elif bzgrep -qE "automake(.*): not found" $1; then
  reason="automake"
elif bzgrep -q 'Checksum mismatch' $1; then
  reason="checksum"
elif bzgrep -qE "(clang: error: unable to execute command|error: cannot compile this.*yet|error: clang frontend command failed|error:.*ignoring directive for now|error: (invalid|unknown) argument|error: (invalid|unknown use of) instruction mnemonic|error:.*please report this as a bug)" $1; then
  reason="clang-bug"
elif bzgrep -q "Shared object \"libc.so.6\" not found, required by" $1; then
  reason="compat6x"
elif bzgrep -q "Fatal error .failed to get sysctl kern.sched.cpusetsize" $1; then
  reason="cpusetsize"
elif bzgrep -qE "pkg_(add|create):.*(can't find enough temporary space|projected size of .* exceeds available free space)" $1; then
  reason="disk_full"
elif bzgrep -qE "((Can't|unable to) open display|Cannot open /dev/tty for read|RuntimeError: cannot open display|You must run this program under the X-Window System)" $1; then
  reason="DISPLAY"
elif bzgrep -qE '(No checksum recorded for|(Maybe|Either) .* is out of date, or)' $1; then
  reason="distinfo_update"
elif bzgrep -qE "(error.*hostname nor servname provided|fetch:.*No address record|Member name contains .\.\.)" $1; then
  reason="fetch"
elif bzgrep -qE "(pnohang: killing make checksum|fetch: transfer timed out)" $1; then
  reason="fetch_timeout"
elif bzgrep -q "See <URL:http://gcc.gnu.org/bugs.html> for instructions." $1; then
  reason="gcc_bug"
elif bzgrep -qE "(missing separator|mixed implicit and normal rules|recipe commences before first target).*Stop" $1; then
  reason="gmake"
elif bzgrep -qE "(Run-time system build failed for some reason|tar: Error opening archive: Failed to open.*No such file or directory)" $1; then
  reason="install_error"
elif bzgrep -qE "(cc: .*libintl.*: No such file or directory|cc: ndbm\.so: No such file or directory|error: linker command failed|error: The X11 shared library could not be loaded|libtool: link: cannot find the library|relocation against dynamic symbol|Shared object.*not found, required by)" $1; then
  reason="linker_error"
elif bzgrep -q "libtool: finish: invalid argument" $1; then
  reason="libtool"
elif bzgrep -q "Could not create Makefile" $1; then
  reason="makefile"
elif bzgrep -v "regression-test.continuing" $1 | grep -qE "make.*(cannot open [Mm]akefile|don.t know how to make|fatal errors encountered|No rule to make target|built-in)"; then
  reason="makefile"
elif bzgrep -q "/usr/.*/man/.*: No such file or directory" $1; then
  reason="manpage"
elif bzgrep -q "out of .* hunks .*--saving rejects to" $1; then
  reason="patch"
elif bzgrep -qE "((perl|perl5.6.1):.*(not found|No such file or directory)|cp:.*site_perl: No such file or directory|perl(.*): Perl is not installed, try .pkg_add -r perl|Perl .* required--this is only version)" $1; then
  reason="perl"
elif bzgrep -qE "(Abort trap|Bus error|Error 127|Killed: 9|Signal 1[01])" $1; then
  reason="process_failed"
elif bzgrep -qE "(USER.*PID.*TIME.*COMMAND|pnohang: killing make package|Killing runaway|Killing timed out build)" $1; then
  reason="runaway_process"
elif bzgrep -qE "(/usr/bin/ld: cannot find -l(pthread|XThrStub)|cannot find -lc_r|Error: pthreads are required to build this package|Please install/update your POSIX threads (pthreads) library|requires.*thread support|: The -pthread option is deprecated)" $1; then
  reason="threads"
elif bzgrep -qi 'read-only file system' $1; then
  reason="WRKDIR"

# Although these can be fairly common, and thus in one sense ought to be
# earlier in the evaluation, in practice they are most often secondary
# types of errors, and thus need to be evaluated after all the specific
# cases.

elif bzgrep -qE "\.(c|cc|cxx|cpp|h|y)[0-9:]+ error: .*-Werror" $1; then
  reason="clang_werror"
elif bzgrep -qE 'cc1.*warnings being treated as errors' $1; then
  reason="compiler_error"
elif bzgrep -q 'tar: Error exit delayed from previous errors' $1; then
  reason="install_error"
elif bzgrep -q "Cannot stat: " $1; then
  reason="configure_error"
elif bzgrep -q "error in dependency .*, exiting" $1; then
  reason="depend_package"
elif bzgrep -q "/usr/bin/ld: cannot find -l" $1; then
  reason="linker_error"
elif bzgrep -q "^#error \"" $1; then
  reason="explicit_error"
elif bzgrep -q "cd: can't cd to" $1; then
  reason="NFS"
elif bzgrep -qE "(pkg_create: make_dist: tar command failed with code|pkg-static: lstat|pkg-static DEVELOPER_MODE: Plist error:|Error: check-plist failures)" $1; then
  reason="PLIST"
elif bzgrep -q "pkg-static: package field incomplete" $1; then
  reason="MANIFEST"
elif bzgrep -q "Segmentation fault" $1; then
  reason="segfault"

else
  reason="???"
fi

echo "$reason"

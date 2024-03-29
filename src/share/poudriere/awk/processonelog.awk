# Read a single errorlogfile and output a reason.
#
# Originally factored out of portbuild's processonelog
# not up-to-date with:
# http://www.marcuscom.com:8080/cgi-bin/cvsweb.cgi/portstools/tinderbox/sql/values.{lp|pfp|pfr}

function found(reason) {
	if (!REASON && !REASON_LAST) {
		REASON = reason
	}
}
function found_last(reason) {
	if (!REASON) {
		REASON_LAST = reason
	}
}

$0 ~ "(Error: mtree file ./etc/mtree/BSD.local.dist. is missing|error in pkg_delete|filesystem was touched prior to .make install|list of extra files and directories|list of files present before this port was installed|list of filesystem changes from before and after|Error: Files or directories left over|Error: Filesystem touched during build)" {
	found("mtree");
}
# note: must run before the configure_error check
$0 ~ "Configuration .* not supported" {
	found("arch");
}
$0 ~ "[.](c|cc|cxx|cpp|h|y)[0-9:]+ .+[.][hH](: No such file|' file not found)" {
	found("missing_header");
}
$0 ~ "(configure: error:|Script.*configure.*failed unexpectedly|script.*failed: here are the contents of|CMake Error at|fatal error.*file not found)" {
	found("configure_error");
}
$0 ~ "Couldn't fetch it - please try" {
	found("fetch");
}
$0 ~ "Error: shared library \".*\" does not exist" {
	found("LIB_DEPENDS");
}
$0 ~ "ld: error: duplicate symbol:" {
	found("duplicate_symbol");
}
$0 ~ "error: .* create dynamic relocation .* against symbol: .* in readonly segment" {
	found("lld_linker_error");
}
/(parse error|too (many|few) arguments to|argument.*doesn.*prototype|incompatible type for argument|conflicting types for|undeclared \(first use (in )?this function\)|incorrect number of parameters|has incomplete type and cannot be initialized|error: storage size.* isn.t known|command .cc. terminated by signal 4)/ {
	found("compiler_error");
}
$0 ~ "(ANSI C.. forbids|is a contravariance violation|changed for new ANSI .for. scoping|[0-9]: passing .* changes signedness|lacks a cast|redeclared as different kind of symbol|invalid type .* for default argument to|wrong type argument to unary exclamation mark|duplicate explicit instantiation of|incompatible types in assignment|assuming . on overloaded member function|call of overloaded .* is ambiguous|declaration of C function .* conflicts with|initialization of non-const reference type|using typedef-name .* after|[0-9]: size of array .* is too large|fixed or forbidden register .* for class|assignment of read-only variable|error: label at end of compound statement|error:.*(has no|is not a) member|error:.*is (private|protected)|error: uninitialized member|error: unrecognized command line option)" {
	found("new_compiler_error");
}
# must preceed badc++
$0 ~ "ld: error:.*undefined (reference|symbol).*std::" {
	found("clang11");
}
$0 ~ "(syntax error before|friend declaration|no matching function for call to|.main. must return .int.|invalid conversion (between|from)|cannot be used as a macro name as it is an operator in C[+][+]|is not a member of type|after previous specification in|no class template named|because worst conversion for the former|better than worst conversion|no match for.*operator|no match for call to|undeclared in namespace|is used as a type, but is not|error: array bound forbidden|error: class definition|error: expected constructor|error: there are no arguments|error:.*cast.*loses precision|ISO C[+][+]|error: invalid pure specifier|error: invalid (argument type|integral value|operand|token|use of a cast|value)|error: expected.*(at end of declaration|expression|identifier)|error:.*not supported|error:.*assert failed|error: expected unqualified-id|error: non-constant-expression cannot be narrowed|error: cannot assign to variable|error: no type.*in namespace|error: constant expression evaluates)" {
	found("bad_C++_code");
}
$0 ~ "error: (array type has incomplete element type|conflicts with new declaration|expected.*before .class|expected primary expression|extra qualification .* on member|.*has incomplete type|invalid cast.*type .* to type|invalid lvalue in (assignment|decrement|increment|unary)|invalid storage class for function|lvalue required as (increment operator|left operand)|.*should have been declared inside|static declaration of.*follows non-static declaration|two or more data types in declaration specifiers|.* was not declared in this scope)" {
	found("gcc4_error");
}
$0 ~ "^(cp|install|make|pkg-static|strip|tar):.*No such file" {
	found("install_error");
}
$0 ~ "(conflicts with installed package|installs files into the same place|is already installed - perhaps an older version|You may wish to ..make deinstall.. and install this port again)" {
	found("depend_object");
}
$0 ~ "(error: a parameter list without types|error: C++ requires a type specifier|error: allocation of incomplete type|error: array is too large|error: binding of reference|error: call to func.*neither visible|error: called object type|error: cannot combine with previous.*specifier|error: cannot initialize (a parameter|a variable|return object)|error: cannot pass object|error:.*cast from pointer|error: comparison of unsigned.*expression.*is always|error: (conversion|use of operator).*(is ambiguous|specifies type)|error:.*converts between pointers to integer|error: declaration of.*shadows template parameter|error:.*declared as an array with a negative size|error: default arguments cannotbe added|error: default initialization of an object|error: definition.*not in a namespace|error:.*directive requires a positive integer argument|error: elaborated type refers to a typedef|error: exception specification|error: explicit specialization.*after instantiation|error: explicitly assigning a variable|error: expression result unused|error: fields must have a constant size|error: flexible array member|error: (first|second) (argument|parameter) of .main|error: format string is not a string literal|error: function.*is not needed|error: global register values are not supported|error:.*hides overloaded virtual function|error: if statement has empty body|error: illegal storage class on function|error: implicit (conversion|declaration|instantiation)|error: indirection.*will be deleted|error: initializer element is not.*constant|error: initialization of pointer|error: indirect goto might cross|error:.*is a (private|protected) member|error: member (of anonymous union|reference)|error: no matching member|error: non-const lvalue|error: non-void function.*should return a value|error: no (matching constructor|member named|viable overloaded)|error: parameter.*must have type|error: passing.*(a.*value|incompatible type)|error: qualified reference|error: redeclaration of.*built-in type|error:.*requires a (constant expression|pointer or reference|type specifier)|error: redefinition of|error: switch condition has boolean|error: taking the address of a temporary object|error: target.*conflicts with declaration|error:.*unable to pass LLVM bit-code files to linker|error: unexpected token|error: unknown (machine mode|type name)|error: unsupported option|error: unused (function|parameter)|error: use of (GNU old-style field designator|undeclared identifier|unknown builtin)|error: using the result of an assignment|error: variable.*is unitialized|error: variable length array|error: void function.*should not return a value|the clang compiler does not support|Unknown depmode none)" {
	found("clang");
}
# must follow "clang" {
$0 ~ "(/usr/libexec/elf/ld: cannot find|undefined reference to|cannot open -l.*: No such file|error: linker command failed with exit code 1)" {
	found("linker_error");
}

# below here are the less common items

$0 ~ "(.s: Assembler messages:|Cannot (determine .* target|find the byte order) for this architecture|^cc1: bad value.*for -mcpu.*switch|could not read symbols: File in wrong format|[Ee]rror: [Uu]nknown opcode|error.*Unsupported architecture|ENDIAN must be defined 0 or 1|failed to merge target-specific data|(file not recognized|failed to set dynamic section sizes): File format not recognized|impossible register constraint|inconsistent operand constraints in an .asm|Invalid configuration.*unknown.*machine.*unknown not recognized|invalid lvalue in asm statement|is only for.*, and you are running|not a valid 64 bit base/index expression|relocation R_X86_64_32.*can not be used when making a shared object|relocation truncated to fit: |shminit failed: Function not implemented|The target cpu, .*, is not currently supported.|This architecture seems to be neither big endian nor little endian|unknown register name|Unable to correct byte order|Unsupported platform, sorry|won't run on this architecture|error: invalid output constraint .* in asm|error: unsupported inline asm|error: invalid (instruction|operand)|error: Please add support for your architecture|error: unrecognized machine type|error: [Uu]nknown endian|<inline asm>.* error:|error: unrecognized instruction)" {
	found("arch");
}
$0 ~ "Checksum mismatch" {
	found("checksum");
}
$0 ~ "(clang: error: unable to execute command|error: cannot compile this.*yet|error: clang frontend command failed|error:.*ignoring directive for now|error: (invalid|unknown) argument|error: (invalid|unknown use of) instruction mnemonic|error:.*please report this as a bug|LLVM ERROR: )" {
	found("clang-bug");
}
$0 ~ "((Can't|unable to) open display|Cannot open /dev/tty for read|RuntimeError: cannot open display|You must run this program under the X-Window System)" {
	found("DISPLAY");
}
$0 ~ "(No checksum recorded for|(Maybe|Either) .* is out of date, or)" {
	found("distinfo_update");
}
$0 ~ "(error.*hostname nor servname provided|fetch:.*No address record|Member name contains .[.][.])" {
	found("fetch");
}
$0 ~ "(pnohang: killing make checksum|fetch: transfer timed out)" {
	found("fetch_timeout");
}
$0 ~ "See <URL:http://gcc.gnu.org/bugs.html> for instructions." {
	found("gcc_bug");
}
$0 ~ "(Run-time system build failed for some reason|tar: Error opening archive: Failed to open.*No such file or directory)" {
	found("install_error");
}
$0 ~ "(cc: .*libintl.*: No such file or directory|cc: ndbm[.]so: No such file or directory|error: linker command failed|error: The X11 shared library could not be loaded|libtool: link: cannot find the library|relocation against dynamic symbol|Shared object.*not found, required by|ld: unrecognized option|error: ld returned.*status )" {
	found("linker_error");
}
$0 ~ "Could not create Makefile" {
	found("makefile");
}
$0 !~ /regression-test[.]continuing/ && $0 ~ "make.*(cannot open [Mm]akefile|don.t know how to make|fatal errors encountered|No rule to make target|built-in)" {
	found("makefile");
}
$0 ~ "/usr/.*/man/.*: No such file or directory" {
	found("manpage");
}
$0 ~ "(out of .* hunks .*--saving rejects to|FAILED to apply cleanly FreeBSD patch)" {
	found("patch");
}
$0 ~ "(Abort trap|Bus error|Error 127|Killed: 9|Signal 1[01])" {
	found("process_failed");
}
$0 ~ "error: .regparm. is not valid on this platform" {
	found("regparm");
}
$0 ~ "(USER.*PID.*TIME.*COMMAND|pnohang: killing make package|Killing runaway|Killing timed out build)" {
	found("runaway_process");
}
# this is usually a second-order effect
$0 ~ "#warning \"this file includes <sys/termios.h>" {
	found("termios");
}
$0 ~ "(/usr/bin/ld: cannot find -l(pthread|XThrStub)|cannot find -lc_r|Error: pthreads are required to build this package|Please install/update your POSIX threads (pthreads) library|requires.*thread support|: The -pthread option is deprecated|error: reference to .thread. is ambiguous)" {
	found("threads");
}
$0 ~ "Read-only file system" {
	found("WRKDIR");
}

# Although these can be fairly common, and thus in one sense ought to be
# earlier in the evaluation, in practice they are most often secondary
# types of errors, and thus need to be evaluated after all the specific
# cases.

$0 ~ "[.](c|cc|cxx|cpp|h|y)[0-9:]+ error: .*-Werror" {
	found("clang_werror");
}
$0 ~ "cc1.*warnings being treated as errors" {
	found("compiler_error");
}
$0 ~ "core dumped" {
	found("coredump");
}
$0 ~ "tar: Error exit delayed from previous errors" {
	found("install_error");
}
$0 ~ "Cannot stat: " {
	found("configure_error");
}
$0 ~ "error in dependency .*, exiting" {
	found("depend_package");
}
$0 ~ "/usr/bin/ld: cannot find -l" {
	found("linker_error");
}
$0 ~ "^#error \"" {
	found("explicit_error");
}
$0 ~ "(Segmentation fault|signal: 11, SIGSEGV)" {
	found("segfault");
}
# must come after segfault
$0 ~ "(process didn.t exit successfully:.*build-script-build|try .rustc --explain)" {
	found("rust");
}
$0 ~ "ninja: build stopped: subcommand failed" {
	found("ninja");
}
/=======================<phase: .*/     { found_last($2); }

END {
	if (REASON_LAST) {
		REASON = REASON_LAST
	}
	if (!REASON) {
		REASON = "???"
	}
	print REASON
}

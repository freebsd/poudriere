. ./common.sh

case "$(type wc)" in
*"is a shell builtin") ;;
*) exit 77 ;;
esac

val=$(echo 1 | wc -l)
assert "1" ${val}

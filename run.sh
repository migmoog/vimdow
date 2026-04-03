nobuild=0
userargs=()
for ((i=1; i <= $#; i++)); do
  arg=${!i}
  if [ "$arg" == "no-build" ]; then
    nobuild=1
  fi

  if [ "$arg" == "--" ]; then
    userargs=("${@:i}")
    break
  fi
done

if [ $nobuild -eq 0 ]; then
  echo "Building..."
  ./build.sh
else
  echo "Skipping build"
fi


case "$1" in
  editor|e)
    godot -e --path godot "${userargs[@]}";;
  standalone|s)
    godot --path godot "${userargs[@]}";;
  *)
    echo "Not a handled case: \"$1\""
    exit 1;;
esac

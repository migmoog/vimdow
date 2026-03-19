if [ "$2" != "no-build" ]; then
   ./build.sh
fi

# if [ "$1" != "no-build" ]; then
#   source build.sh
# fi
#
# godot -e --path godot
#
case "$1" in
  editor|e)
    godot -e --path godot;;
  standalone|s)
    godot --path godot;;
  *)
    echo "Not a handled case: \"$MODE\"";;
esac

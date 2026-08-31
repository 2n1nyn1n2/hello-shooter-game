# format source
echo "checking json formatting"
npm run format-json-check

echo "checking godot script formatting"
gdformat . --check

# format source
## (run from parent directory, the one that contains package.json)

echo "doing json formatting"
npm run format-json

echo "doing godot script formatting"
gdformat .

# check if source is formatted.
./ci/check-format-source.sh
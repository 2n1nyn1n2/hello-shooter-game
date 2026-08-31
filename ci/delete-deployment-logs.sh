# delete deployment logs
PATH_PARENT=$(basename "$PWD")
PATH_GRANDPARENT=$(basename "$(dirname "$PWD")")
REPO="${PATH_GRANDPARENT}/${PATH_PARENT}"
echo "git url https://github.com/${PATH_GRANDPARENT}/${PATH_PARENT}.git"

for ID in $(gh api --method GET "/repos/$REPO/deployments?per_page=100" --jq '.[].id'); do
    gh api --method POST /repos/$REPO/deployments/$ID/statuses -f "state=inactive" > /dev/null 2>&1
    gh api --method DELETE /repos/$REPO/deployments/$ID > /dev/null 2>&1
    echo "Deleted deployment $ID"
done
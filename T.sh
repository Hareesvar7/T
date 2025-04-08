echo "---------------------------finishing the env variable list---------------------------"

count=0
env=${maf_deploy_env}
num=$(jq length /tmp/${env}_backend.json)

if [ "$num" -eq 0 ]; then
  echo "There is nothing to deploy in BE"
  echo "BE DEPLOYMENT IS SUCCESSFUL"
  exit 0
else
  while [ $count -lt $num ]; do

    module_name=$(cat /tmp/${env}_backend.json | jq -c -r ".[$count].name")
    version=$(cat /tmp/${env}_backend.json | jq -c -r ".[$count].version")
    rollback_version=$(cat /tmp/${env}_backend.json | jq -c -r ".[$count].rollback_version")

    if [ "$version" == "null" ]; then
      version=$rollback_version
    fi

    echo "-------------------VD DOWNLOADING ARTIFACT STARTS FOR: $module_name ---------------------"

    # JFrog Download Attempts
    jfrog rt dl conops-npm-${type}-local/${module_name}/${version}/${module_name} --flat --recursive --server-id conops
    if [ ! -e "${module_name}/*" ]; then
      jfrog rt dl conops-npm-staging-local/${module_name}/${version}/${module_name} --flat --recursive --server-id conops
    fi
    if [ ! -e "${module_name}/*" ]; then
      jfrog rt dl conops-npm-scratch-local/${module_name}/${version}/${module_name} --flat --recursive --server-id conops
    fi

    # Error if artifact not found
    if [ ! -e "${module_name}" ] || [ -z "$(ls -A ${module_name})" ]; then
      echo "ERROR: Failed to download the artifact for $module_name (Neither found in $type/staging nor scratch)"
      echo "Exiting..."
      exit 1
    else
      echo "Artifacts downloaded successfully"
    fi

    echo "-------------------VD DOWNLOADING ARTIFACT DONE FOR: $module_name ---------------------"
    echo "-------------------VD STARTING $module_name DEPLOYMENT ---------------------"

    ls -A
    cd ${module_name}

    if [ -e "app-settings.sh" ]; then
      chmod +x app-settings.sh
      echo "-------------------VD READING FROM SPECIFIC DEPLOYMENT SCRIPT ---------------------"
      ./app-settings.sh
      echo "-------------------VD READING FROM SPECIFIC DEPLOYMENT SCRIPT DONE ---------------------"
    fi

    # Handle special case: prc-data-injection-service
    if [ "$module_name" == "prc-data-injection-service" ]; then
      echo "-------------------VD DEPLOYING $module_name TO AZURE BLOB STORAGE ---------------------"
      az storage blob upload \
        --account-name "${STORAGE_ACCOUNT}" \
        --container-name "${CONTAINER_NAME}" \
        --name "${module_name}/v${version}/artifact.zip" \
        --file artifact.zip \
        --auth-mode key \
        --account-key "${STORAGE_KEY}" \
        --overwrite
      echo "-------------------VD BLOB DEPLOYMENT DONE FOR $module_name ---------------------"
    else
      # Regular Azure Function App Deployment
      az functionapp deployment source config-zip \
        -g smarfactory-resource-group \
        -n ${FUNCTIONAPP_NAME_PREFIX}-${module_name} \
        --src ${module_name}
    fi

    cd ..
    rm -rf ${module_name}

    echo "-------------------VD $module_name WITH VERSION:$version DEPLOYMENT ENDS ---------------------"

    count=$((count+1))
  done
fi

#!/usr/bin/env bash

function find_all_test_cases {
  find . -name "main.tf" -exec dirname {} \; | grep -v "\.terraform"
}

function read_rerun {
  TOOL=${1:?'*'}
  if [ ! -f .rerun ]; then echo ".rerun not found" && exit 1; fi
  cat .rerun | while read line
  do
    find $line -name "${TOOL}_results.txt" -delete
    echo "$line"
  done
}

# Checkov
function run_checkov {
  docker pull bridgecrew/checkov:latest
  docker run -t -v $PWD:/tf bridgecrew/checkov --version >version_checkov.txt
  for test_case in $@; do
    echo $test_case
    ORG_PATH=$PWD
    cd $test_case
    if [ ! -f checkov_results.txt ]; then docker run -t -v $PWD:/tf bridgecrew/checkov --quiet -d /tf | sed 's/\[[0-9;]*m//g' | sed "s~$ORG_PATH~tool-compare~" >checkov_results.txt; fi
    cd $ORG_PATH
  done
}

# tfsec
function run_tfsec {
  docker pull tfsec/tfsec:latest
  docker run -t -v $PWD:/tf tfsec/tfsec --version >version_tfsec.txt
  for test_case in $@; do
    echo $test_case
    ORG_PATH=$PWD
    cd $test_case
    if [ ! -f tfsec_results.txt ]; then docker run --rm -v "$(pwd):/src" tfsec/tfsec /src --no-color | sed "s~$ORG_PATH~tool-compare~" >tfsec_results.txt; fi
    cd $ORG_PATH
  done
}

# KICS
function run_kics {
  #docker pull checkmarx/kics:latest
  docker run -t -v $PWD:/tf checkmarx/kics:latest version | awk '{print $NF}' >version_kics.txt
  for test_case in $@; do
    echo $test_case
    ORG_PATH=$PWD
    cd $test_case
    if [ ! -f kics_results.txt ]; then docker run --rm -v "$(pwd):/src" checkmarx/kics:latest scan --no-progress -p /src | sed "s~$ORG_PATH~tool-compare~" | grep -v "Executing queries" >kics_results.txt; fi
    cd $ORG_PATH
  done
}

# Terrascan
function run_terrascan {
  brew install terrascan
  terrascan version | awk '{print $NF}' >version_terrascan.txt
  for test_case in $@; do
    echo $test_case
    ORG_PATH=$PWD
    cd $test_case
    if [ ! -f terrascan_results.txt ]; then terrascan scan | sed "s~$ORG_PATH~tool-compare~" >terrascan_results.txt; fi
    cd $ORG_PATH
  done
}

# Snyk
function run_snyk {
  if [ -z "$SNYK_TOKEN" ]; then
    echo "To run this script, you'll need to provide the SNYK_TOKEN environment variable."
    exit 1
  fi

  docker pull snyk/snyk-cli:docker
  docker run -t -v empty:/project -e SNYK_TOKEN snyk/snyk-cli:docker --version | tail -n 1 >version_snyk.txt
  for test_case in $@; do
    echo $test_case
    ORG_PATH=$PWD
    cd $test_case
    if [ ! -f snyk_results.txt ]; then docker run --rm -v "$(pwd):/project" -e SNYK_TOKEN snyk/snyk-cli:docker iac test --experimental /project | sed "s~$ORG_PATH~tool-compare~" >snyk_results.txt; fi
    cd $ORG_PATH
  done
}

# Cloudrail
function run_cloudrail {
  if [ -z "$CLOUDRAIL_API_KEY" ]; then
    echo "To run this script, you'll need to provide the CLOUDRAIL_API_KEY environment variable."
    exit 1
  fi

  docker pull indeni/cloudrail-cli:latest
  docker run -t -v $PWD:/tf indeni/cloudrail-cli --version | awk '{print $NF}' >version_cloudrail.txt
  for test_case in $@; do
    echo $test_case
    ORG_PATH=$PWD
    cd $test_case
    if [ ! -f cloudrail_results.txt ]; then docker run --rm -v $PWD:/data -e CLOUDRAIL_API_KEY indeni/cloudrail-cli run --tf-plan plan.out --output-file cloudrail_results.txt --no-cloud-account --auto-approve -v; fi
    cd $ORG_PATH
  done
}

function run_all {
  echo Now running Checkov on all cases
  run_checkov $1
  echo Now running Cloudrail on all cases
  run_cloudrail $1
  echo Now running KICS on all cases
  run_kics $1
  echo Now running Snyk on all cases
  run_snyk $1
  echo Now running Terrascan on all cases
  run_terrascan $1
  echo Now running TFsec on all cases
  run_tfsec $1
}

if [[ $1 == *"all" ]] || [[ $1 == *"cloudrail" ]]; then
  # Set up AWS access for plan
  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "To run this script, you'll need AWS credentials (for use with terraform plan)."
    exit 1
  fi
  export AWS_REGION=us-west-1

  # Generate all plan files
  echo Generating plan files, where they do not exist yet

  find . -name "main.tf" -exec dirname {} \; | grep -v "\.terraform" | while read -r test_case; do
    echo $test_case
    ORG_PATH=$PWD
    cd $test_case
    if [ ! -f plan.out ]; then
      terraform init
      terraform plan -out=plan.out
    fi
    cd $ORG_PATH
  done
fi

case $1 in
run_checkov)
  echo Now running Checkov on all cases
  "$1" $(find_all_test_cases)
  exit
  ;;
rerun_checkov)
  echo Now running Checkov on selected cases
  run_checkov $(read_rerun "checkov")
  exit
  ;;
run_cloudrail)
  echo Now running Cloudrail on all cases
  "$1" $(find_all_test_cases)
  exit
  ;;
rerun_cloudrail)
  echo Now running Cloudrail on selected cases
  run_cloudrail $(read_rerun "cloudrail")
  exit
  ;;
run_kics)
  echo Now running KICS on all cases
  "$1" $(find_all_test_cases)
  exit
  ;;
rerun_kics)
  echo Now running KICS on selected cases
  run_kics $(read_rerun "kics")
  exit
  ;;
run_snyk)
  echo Now running Snyk on all cases
  "$1" $(find_all_test_cases)
  exit
  ;;
rerun_snyk)
  echo Now running Snyk on selected cases
  run_snyk $(read_rerun "snyk")
  exit
  ;;
run_terrascan)
  echo Now running Terrascan on all cases
  "$1" $(find_all_test_cases)
  exit
  ;;
rerun_terrascan)
  echo Now running Terrascan on selected cases
  run_terrascan $(read_rerun "terrascan")
  exit
  ;;
run_tfsec)
  echo Now running TFsec on all cases
  "$1" $(find_all_test_cases)
  exit
  ;;
rerun_tfsec)
  echo Now running TFsec on selected cases
  run_tfsec $(read_rerun "tfsec")
  exit
  ;;
rerun_all)
  run_all $(read_rerun)
  exit
  ;;
*)
  run_all $(find_all_test_cases)
  exit
  ;;
esac

#!/bin/bash
set -eu

cd $(dirname $0) && cd ../

CFN_TEMPLATE="./yamldir/glue.yaml"
GLUE_SCRIPTS_DIR="glue-job-script"
SCRIPT_NAME="job_data_transfer.py"
GlueScriptsFilename="${GLUE_SCRIPTS_DIR}/${SCRIPT_NAME}"

APP_NAME="gluetest"
CFN_STACK_NAME="${APP_NAME}"

CFN_REGION="ap-northeast-1"
AWSAccountID=$(aws sts get-caller-identity | jq -r '.Account')

GlueScriptsBucket="${APP_NAME}-${AWSAccountID}-scripts"
GlueResultsBucket="${APP_NAME}-${AWSAccountID}-results"
GlueTempBucket="${APP_NAME}-${AWSAccountID}-temp"


## "(〇〇)"の部分は実際の環境に合わせて埋めてください
ClusterEndpoint="(RDSのDBクラスターのエンドポイント, EC2ではホスト)"
ConnectionSecret="(Glueコネクションで使用するMySQLユーザのシークレット名)"
GlueSecurityGroupVpcID="(Glueで使用するセキュリティグループのVPCのID)"
GlueConnectionSubnetID="(Glue Connectionで使用するサブネットのID)"
GlueConnectionSubnetAZName="(Glue Connectionで使用するサブネットのAZ名 例:ap-northeast-1)"
SnsTopicName="(ジョブ実行失敗を通知するSNSトピック名)"
SnsTopicArn="(ジョブ実行失敗を通知するSNSトピックARN)"


JDBCString="jdbc:mysql://${ClusterEndpoint}:3306/information_schema"
ConnectionName="${APP_NAME}"

aws cloudformation deploy \
  --stack-name ${CFN_STACK_NAME} \
  --template-file ${CFN_TEMPLATE} \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --parameter-overrides \
  AppName=${APP_NAME} \
  ConnectionName=${ConnectionName} \
  JDBCString=${JDBCString} \
  Secret=${ConnectionSecret} \
  GlueScriptsBucket=${GlueScriptsBucket} \
  GlueResultsBucket=${GlueResultsBucket} \
  GlueTempBucket=${GlueTempBucket} \
  GlueScriptsFilename=${GlueScriptsFilename} \
  GlueSecurityGroupVpcID=${GlueSecurityGroupVpcID} \
  GlueConnectionSubnetID=${GlueConnectionSubnetID} \
  GlueConnectionSubnetAZName=${GlueConnectionSubnetAZName} \
  SnsTopicArn=${SnsTopicArn} \
  SnsTopicName=${SnsTopicName} \
  --no-fail-on-empty-changeset


### AWS::Glue::SecurityConfigurationがInternal Failureになってエラーになるので、CFn実行後にCLIで作成
SecurityConfigurationName="${APP_NAME}-security-config"

SecurityExists=`aws glue get-security-configurations \
    | jq '.SecurityConfigurations[] | select(.Name == "'${SecurityConfigurationName}'") | .Name' \
    | tr -d '"'`

if [ -n "${SecurityExists}" ]; then
    aws glue delete-security-configuration \
        --name ${SecurityConfigurationName} \
        > /dev/null
fi

KmsKeyName="GlueLogsEncryptionKey-ARN"
KmsKeyArn=`aws cloudformation describe-stacks \
    --stack-name ${CFN_STACK_NAME} \
    | jq '.Stacks[].Outputs[] | select(.ExportName == "'${KmsKeyName}'") | .OutputValue' \
    | tr -d '"'`

aws glue create-security-configuration \
    --name ${SecurityConfigurationName} \
    --encryption-configuration "CloudWatchEncryption={CloudWatchEncryptionMode=SSE-KMS,KmsKeyArn=${KmsKeyArn}}" \
    > /dev/null

### ジョブのコードのデプロイ
aws s3 rm s3://${GlueScriptsBucket} --recursive > /dev/null
aws s3 cp ${GLUE_SCRIPTS_DIR} s3://${GlueScriptsBucket}/${GLUE_SCRIPTS_DIR}/ --recursive > /dev/null
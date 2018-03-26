# psqltools
Postres scripts for pg_dump and AWS Cloudwatch

Uses pg_dump to backup all of the databases on a given RDS Postgresql instance

## Features
- Streams backups to S3 usng the AWS CLI
- Uses AWS Systems Manager Secure String  Parameter Store for database passwords
- Logs to AWS Cloudwatch

## Requirements
- jq - manipulate JSON via Bash; install with 'yum install jq' on CentOS, 'brew install jq' on macOS with Homebrew
- bash
- AWS security groups open to your RDS instance to be backed up
- Write permissions on a given S3 bucket to store backup files
- IAM permissions to your Parameter store

## Using
```rds_pg_dumpall -r rds_instances -s logStreamName -g logGroupName -e region -b s3bucket u username -p port```

Mandatory parameters
-r Command separated list of RDS instances to backup<br>
-s Log Stream Name (must be created in advance)<br>
-g Log Group Name  (must ve created in advance)<br>
-p The port to use for psql to connect to RDS instances. All rds instances specified will use this port for the connection.<br>
-e AWS region, e.g., us-east-1<br>
-b S3 bucket. You must have write permissions to this bucket.<br>

rds_pg_dumpall will query the AWS Systems Manager parameter store to get the password for the databases to be backed up. The parameter store key is in the format ```rdsInstance_databaseName```, for example 


##### Example
```
./rds_pg_dumpall.sh -r mydbinstance.c15lzdctuff2.us-east-1.rds.amazonaws.com -s mydbinstance -g aws_rds_postgres -b dbtools-backups -u master -p 5432 -e us-east-1
```





# psqltools
Postres scripts for pg_dump and AWS Cloudwatch

Uses pg_dump to backup all of the databases on a given RDS Postgresql instance

Fearures:
- Streams backups to S3 usng the AWS CLI
- Uses AWS Systems Manager Secure String  Parameter Store for database passwords

Requirements:
- jq - manipulate JSON via Bash; install with 'yum install jq'
- bash
- security groups open to your RDS instance to be backed up
- Write permissions on a given S3 bucket to store backup files
- IAM permssions to your Parameter store



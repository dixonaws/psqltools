#!/bin/bash

rds_host="mydbinstance.c15lzdctuff2.us-east-1.rds.amazonaws.com"
rds_port="5432"
log_group_name="aws_rds_postgres"
log_stream_name="mydbinstance"
region="us-east-1"
db_username="master"

# query the RDS instance for a list of databases
db_password=`aws ssm get-parameter --with-decryption --name mydbinstance.c15lzdctuff2.us-east-1.rds.amazonaws.com_db0 --region $region |jq -r '.Parameter.Value'`

databases=$(psql --dbname="postgresql://$db_username:$db_password@$rds_host:$rds_port/postgres" --command="SELECT datname FROM pg_database WHERE datistemplate=false;" --no-align --tuples-only)

# iterate through the list of datbases and back up each one with pg_dump
for dbname in $databases; do
	datetimestring=$(date +%m-%d-%Y_%T%z)

	echo -n "Backing up $dbname... "

	# you can't backup the rdsadmin database on RDS, so we skip it
	if [ $dbname = "rdsadmin" ]
	then 
		echo "skipping rdsadmin"
		continue
	fi

	targetfilename=$dbname-$datetimestring-psql.tar

	# get the database password from the AWS Systems Manager paerameter store (your IAM user must have permissions to do this)
	db_password=`aws ssm get-parameter --with-decryption --name "$rds_host"_"$dbname" --region $region |jq -r '.Parameter.Value'`

	# stream the backup of each database directly to S3
	pg_dump --dbname="postgresql://$db_username:$db_password@$rds_host:$rds_port/$dbname" --format=tar | aws s3 cp - s3://dbtools-backups/$targetfilename --quiet

	# get the filesize in S3
	filesize=$(aws s3 ls s3://dbtools-backups/$targetfilename |awk '{print $3}')
	filesizemb=$(expr $filesize / 1024 / 1024)
	filesizekb=$(expr $filesize / 1024)
	echo "done ($targetfilename, $filesizekb KiB)"
	
	# log it
	# get the next sequence token (need this to write to a non-empty log stream)
	token=$(aws logs describe-log-streams --log-group-name $log_group_name --region us-east-1 |grep uploadSequenceToken |awk -F ":" '{print $2}')

	# strip off the quotes and comma from the string
	len=${#token}
	substr=$(expr $len - 5)
	token=${token:2:substr}

	aws logs put-log-events --log-group-name $log_group_name --log-stream-name $log_stream_name --log-events "timestamp=$(echo $(date +%s%N | cut -b1-13)),message='$dbname was backed up ($filesizekb KiB)'" --region us-east-1 --sequence-token $token > /dev/null

done







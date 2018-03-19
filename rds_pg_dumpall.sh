#!/bin/bash

# query the RDS instance for a list of databases
databases=$(psql postgresql://mydbinstance.c15lzdctuff2.us-east-1.rds.amazonaws.com:5432/db0 --username=master --command="SELECT datname FROM pg_database WHERE datistemplate=false;" --no-align --tuples-only)

# iterate through the list of datbases and back up each one with pg_dump
for dbname in $databases; do
	datetimestring=$(date +%m-%d-%Y_%T%z)

	echo -n "Backing up $dbname... "

	# you can't backup rdsadmin database on RDS
	if [ $dbname = "rdsadmin" ]
	then 
		echo "skipping rdsadmin"
		continue
	fi

	targetfilename=$dbname-$datetimestring.psql
	pg_dump --host mydbinstance.c15lzdctuff2.us-east-1.rds.amazonaws.com --port 5432 --username master --dbname=$dbname --no-password > $targetfilename

	# copy to S3 dbtools-backups bucket
	aws s3 cp $targetfilename s3://dbtools-backups

	# get the filesize on the local filesystem
	# filesize=$(ls -lah /home/ec2-user/backups/$targetfilename |awk '{print $5}')

	# get the filesize in S3
	filesize=$(aws s3 ls s3://dbtools-backups/$targetfilename |awk '{print $3}')
	filesizemb=$(expr $filesize / 1024 / 1024)
	filesizekb=$(expr $filesize / 1024)
	echo "done ($targetfilename, $filesizekb KiB)"

	# now, cleanup the local backup files
	echo -n "Cleaning up $targetfilename..."
	rm $targetfilename
	
	# log it
	# get the next sequence token
	token=$(aws logs describe-log-streams --log-group-name aws_rds_postgres --region us-east-1 |grep uploadSequenceToken |awk -F ":" '{print $2}')
	len=${#token}
	substr=$(expr $len - 5)

	# strip off the quotes and comma from the string
	token=${token:2:substr}

	aws logs put-log-events --log-group-name aws_rds_postgres --log-stream-name mydbinstance --log-events "timestamp=$(echo $(date +%s%N | cut -b1-13)),message='$dbname was backed up ($filesizekb KiB)'" --region us-east-1 --sequence-token $token > /dev/null
	echo " done."

done







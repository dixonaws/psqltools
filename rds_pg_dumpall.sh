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
	pg_dump --host mydbinstance.c15lzdctuff2.us-east-1.rds.amazonaws.com --port 5432 --username master --dbname=$dbname --no-password > /home/ec2-user/backups/$targetfilename

	# copy to S3 dbtools-backups bucket
	aws s3 cp /home/ec2-user/backups/$targetfilename s3://dbtools-backups

	# get the filesize on the local filesystem
	# filesize=$(ls -lah /home/ec2-user/backups/$targetfilename |awk '{print $5}')

	# get the filesize in S3
	filesize=$(aws s3 ls s3://dbtools-backups/$targetfilename |awk '{print $3}')
	filesizemb=$(expr $filesize / 1024 / 1024)
	filesizekb=$(expr $filesize / 1024)
	echo "done ($targetfilename, $filesizekb KiB)"
done







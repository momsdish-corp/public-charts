## Description
This chart is intended to help manage backups.

This chart will download files from a s3 bucket, to `/s3-data/`, and update the `/s3-data/.pull` file with the name of the download.

The pod finishes when the /s3-data/.pull file is deleted or .activeDeadlineSeconds is reached.
## Description
This chart is intended to help manage backups.

This chart will upload files to an s3 bucket, and update .latest and .previous files.

The file/directory must be uploaded to `/s3-data/`, and the name of the file/directory must be set in `/s3-data/.push`.

The pod starts when the /s3-data/.push file is created and ends when the files are uploaded or .activeDeadlineSeconds is reached.
## Description
Run automated website tests, set in values.yaml. Check URLs against status codes, expected CSS selectors, redirects.

Refer to the values.yaml for example usage.

## Our Use Case
We use this in-house to test our website after each update, before deploying to production. This way all updates are 
done automatically, and we can be sure that the website is still working as expected.

## Adding Plugins
This chart is designed to be extensible. Simply add your own script to ./plugins/*.sh. You can then add the commands via
values.yaml. Make sure to include the two required flags: `--baseURL` and `--waitBeforeExit`.

Example:
```
baseURL: example.com
waitBeforeExit: 5
plugins:
  downloader:
    - url: example.com
      path: /
      fetch:
        - jpg
        - png
```
Will run
```
/plugins/downloader.sh --baseURL="example.com" --waitBeforeExit="5" --path="/" --fetch="jpg" --fetch="png"
```
Keep in mind that the values will be URL encoded.